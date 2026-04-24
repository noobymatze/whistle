defmodule Whistle.Registrations do
  @moduledoc """
  The Registrations context.
  """

  import Ecto.Query, warn: false
  alias Whistle.Repo

  alias Whistle.Registrations.Registration
  alias Whistle.Registrations.RegistrationView
  alias Whistle.Courses
  alias Whistle.Courses.Course
  alias Whistle.Courses.CourseDate
  alias Whistle.Courses.CourseDateSelection
  alias Whistle.Accounts.User
  alias Whistle.Registrations.Enrollment

  @doc """
  Enrolls a user in one or more courses with full business logic validation.

  Returns a list of results for each course - either {:ok, registration} or {:error, error}.

  ## Examples

      iex> enroll(user, [course1, course2])
      [{:ok, %Registration{}}, {:error, %EnrollmentError{}}]

  """
  def enroll(user, courses, registered_by_user_id \\ nil) when is_list(courses) do
    # First check the 2-course limit
    case check_only_two_courses_with_different_types_allowed(user, courses) do
      {:error, error} ->
        # If global validation fails, all courses fail with this error
        Enum.map(courses, fn _ -> {:error, error} end)

      {:ok, {errors, courses_to_enroll}} ->
        # Some courses may have already been registered - those are errors
        # The rest need capacity checks and enrollment using the transactional enroll_one
        enrollment_results =
          Enum.map(courses_to_enroll, fn course ->
            enroll_one(user, course, registered_by_user_id)
          end)

        # Combine the already-registered errors with enrollment results
        already_registered_errors = Enum.map(errors, fn err -> {:error, err} end)
        already_registered_errors ++ enrollment_results
    end
  end

  @doc """
  Enrolls a user in a single course with validation.

  Uses a transaction with row-level locking to prevent race conditions.
  The user is allowed to participate in a course iff:

    1. There is a seat available.
    2. They have not been signed up for a course of the same type
       this season (except for special G-course logic).

  ## Examples

      iex> enroll_one(user, course)
      {:ok, %Registration{}}

      iex> enroll_one(user, course)
      {:error, :not_allowed}

      iex> enroll_one(user, course)
      {:error, :not_available}

  """
  def enroll_one(user, course, registered_by_user_id \\ nil, date_ids \\ nil) do
    Repo.transaction(fn ->
      if course.online do
        enroll_online(user, course, registered_by_user_id, date_ids)
      else
        enroll_offline(user, course, registered_by_user_id)
      end
    end)
  end

  defp enroll_offline(user, course, registered_by_user_id) do
    # Lock the course to prevent concurrent registrations from exceeding capacity
    _locked_course = Courses.get_and_lock_course(course.id)

    cond do
      not Enrollment.seat_available?(user, course, registrations_for_course(course)) ->
        Repo.rollback({:not_available, course})

      not Enrollment.allowed?(user, course) ->
        Repo.rollback({:not_allowed, course})

      true ->
        persist_registration(user, course, registered_by_user_id)
    end
  end

  defp enroll_online(user, course, registered_by_user_id, date_ids) do
    with {:ok, {mandatory, elective}} <- validate_date_selection(course, date_ids),
         _ = lock_course_dates([mandatory.id, elective.id]),
         :ok <- check_date_capacity(mandatory),
         :ok <- check_date_capacity(elective),
         :ok <- check_date_club_limit(user, course, mandatory),
         :ok <- check_date_club_limit(user, course, elective),
         :ok <- check_allowed_online(user, course) do
      registration = persist_registration(user, course, registered_by_user_id)
      replace_date_selections(registration, [mandatory.id, elective.id])
      registration
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp validate_date_selection(_course, date_ids) when not is_list(date_ids) or date_ids == [] do
    {:error, {:invalid_selection, :date_ids_required}}
  end

  defp validate_date_selection(course, date_ids) do
    if length(date_ids) != length(Enum.uniq(date_ids)) do
      {:error, {:invalid_selection, :duplicate_date_ids}}
    else
      do_validate_date_selection(course, date_ids)
    end
  end

  defp do_validate_date_selection(course, date_ids) do
    dates = Repo.all(from d in CourseDate, where: d.id in ^date_ids)

    wrong_course = Enum.find(dates, fn d -> d.course_id != course.id end)

    mandatory = Enum.filter(dates, &(&1.kind == :mandatory))
    elective = Enum.filter(dates, &(&1.kind == :elective))

    cond do
      wrong_course != nil ->
        {:error, {:invalid_selection, :date_belongs_to_other_course}}

      length(mandatory) != 1 ->
        {:error, {:invalid_selection, :must_select_exactly_one_mandatory}}

      length(elective) != 1 ->
        {:error, {:invalid_selection, :must_select_exactly_one_elective}}

      true ->
        {:ok, {hd(mandatory), hd(elective)}}
    end
  end

  defp lock_course_dates(date_ids) do
    Repo.all(from d in CourseDate, where: d.id in ^date_ids, lock: "FOR UPDATE")
  end

  defp check_dates_in_future(dates) do
    today = Whistle.Timezone.today_local()

    case Enum.find(dates, fn d -> Date.compare(d.date, today) == :lt end) do
      nil -> :ok
      date -> {:error, {:date_in_past, date.id}}
    end
  end

  defp check_date_capacity(%CourseDate{id: id, course_id: course_id} = date, opts \\ []) do
    exclude_registration_id = Keyword.get(opts, :exclude_registration_id)

    query =
      from s in CourseDateSelection,
        join: r in Registration,
        on: r.id == s.registration_id,
        where: s.course_date_id == ^id and is_nil(r.unenrolled_at)

    query =
      if exclude_registration_id do
        from s in query, where: s.registration_id != ^exclude_registration_id
      else
        query
      end

    count = Repo.one(from s in query, select: count(s.id))

    course = Courses.get_course!(course_id)

    if count >= course.max_participants do
      {:error, {:not_available, date}}
    else
      :ok
    end
  end

  defp check_date_club_limit(
         %User{club_id: club_id},
         course,
         %CourseDate{id: id} = date,
         opts \\ []
       ) do
    exclude_registration_id = Keyword.get(opts, :exclude_registration_id)

    query =
      from s in CourseDateSelection,
        join: r in Registration,
        on: r.id == s.registration_id,
        join: u in Whistle.Accounts.User,
        on: u.id == r.user_id,
        where: s.course_date_id == ^id and is_nil(r.unenrolled_at) and u.club_id == ^club_id

    query =
      if exclude_registration_id do
        from s in query, where: s.registration_id != ^exclude_registration_id
      else
        query
      end

    count = Repo.one(from s in query, select: count(s.id))

    if count >= course.max_per_club do
      {:error, {:not_available, date}}
    else
      :ok
    end
  end

  defp check_allowed_online(user, course) do
    query =
      from r in Registration,
        join: c in Course,
        on: c.id == r.course_id,
        where:
          r.user_id == ^user.id and c.season_id == ^course.season_id and is_nil(r.unenrolled_at)

    existing = Repo.all(query)

    cond do
      length(existing) >= 2 ->
        {:error, {:not_allowed, course}}

      Enum.any?(existing, fn r -> r.course_id == course.id end) ->
        {:error, {:not_allowed, course}}

      course.type == "F" and
          Enum.any?(existing, fn r ->
            c = Repo.get!(Course, r.course_id)
            c.type == "F"
          end) ->
        {:error, {:not_allowed, course}}

      true ->
        :ok
    end
  end

  defp persist_registration(user, course, registered_by_user_id) do
    case find_unenrolled_registration(user.id, course.id) do
      nil ->
        attrs = %{user_id: user.id, course_id: course.id, registered_by: registered_by_user_id}

        case create_registration(attrs) do
          {:ok, registration} -> registration
          {:error, changeset} -> Repo.rollback(changeset)
        end

      unenrolled ->
        case reenroll_registration(unenrolled) do
          {:ok, registration} -> registration
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp replace_date_selections(registration, date_ids) do
    Repo.delete_all(from s in CourseDateSelection, where: s.registration_id == ^registration.id)

    Enum.each(date_ids, fn date_id ->
      %CourseDateSelection{}
      |> CourseDateSelection.changeset(%{
        registration_id: registration.id,
        course_date_id: date_id
      })
      |> Repo.insert!()
    end)
  end

  @doc """
  Reschedules one or both selected dates for an existing online registration.

  The registration stays active; only the chosen course dates are replaced.
  """
  def reschedule_online_dates(
        %User{} = user,
        registration_id,
        date_ids_by_kind,
        _acting_user_id \\ nil
      )
      when is_map(date_ids_by_kind) do
    Repo.transaction(fn ->
      with {:ok, {registration, course}} <- active_online_registration(registration_id, user.id),
           {:ok, current_date_ids} <- current_date_ids_by_kind(registration.id),
           {:ok, merged_date_ids} <- merge_date_ids_by_kind(current_date_ids, date_ids_by_kind),
           {:ok, {mandatory, elective}} <-
             validate_date_selection(course, Map.values(merged_date_ids)),
           :ok <- check_dates_in_future([mandatory, elective]),
           _ = lock_course_dates([mandatory.id, elective.id]),
           :ok <- check_date_capacity(mandatory, exclude_registration_id: registration.id),
           :ok <-
             check_date_capacity(elective,
               exclude_registration_id: registration.id
             ),
           :ok <-
             check_date_club_limit(user, course, mandatory,
               exclude_registration_id: registration.id
             ),
           :ok <-
             check_date_club_limit(user, course, elective,
               exclude_registration_id: registration.id
             ) do
        replace_date_selections(registration, [mandatory.id, elective.id])

        registration
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns all emails for users enrolled in a course (excluding unenrolled).

  ## Examples

      iex> get_emails_for_course(course_id)
      ["user1@example.com", "user2@example.com"]

  """
  def get_emails_for_course(course_id) do
    query =
      from(r in RegistrationView,
        where: r.course_id == ^course_id and is_nil(r.unenrolled_at),
        select: r.user_email
      )

    Repo.all(query)
    |> Enum.reject(&is_nil/1)
  end

  # Private helper functions

  defp find_unenrolled_registration(user_id, course_id) do
    query =
      from r in Registration,
        where: r.user_id == ^user_id and r.course_id == ^course_id and not is_nil(r.unenrolled_at)

    Repo.one(query)
  end

  defp reenroll_registration(registration) do
    registration
    |> Registration.changeset(%{unenrolled_at: nil, unenrolled_by: nil})
    |> Repo.update()
  end

  defp check_only_two_courses_with_different_types_allowed(user, courses) do
    # Get season IDs from the courses being enrolled
    season_ids = Enum.map(courses, & &1.season_id) |> Enum.uniq()

    # Get existing registrations for this user in these seasons
    existing_registrations =
      from(r in RegistrationView,
        where: r.user_id == ^user.id and is_nil(r.unenrolled_at) and r.season_id in ^season_ids
      )
      |> Repo.all()

    # Check total course count (existing + new)
    total_count = length(existing_registrations) + length(courses)

    if total_count > 2 do
      {:error, {:only_two_courses_allowed, length(existing_registrations)}}
    else
      # Check for duplicate course IDs (already registered)
      existing_course_ids = MapSet.new(existing_registrations, & &1.course_id)

      {already_registered, can_enroll} =
        Enum.split_with(courses, fn course ->
          MapSet.member?(existing_course_ids, course.id)
        end)

      # Create errors for already registered courses
      errors =
        Enum.map(already_registered, fn course ->
          {:already_registered, user.id, course.id}
        end)

      {:ok, {errors, can_enroll}}
    end
  end

  @doc """
  Returns the list of registrations.

  ## Examples

      iex> list_registrations()
      [%Registration{}, ...]

  """
  def list_registrations do
    Repo.all(Registration)
  end

  @doc """
  Gets a single registration.

  Raises `Ecto.NoResultsError` if the Registration does not exist.

  ## Examples

      iex> get_registration!(123)
      %Registration{}

      iex> get_registration!(456)
      ** (Ecto.NoResultsError)

  """
  def get_registration!(id), do: Repo.get!(Registration, id)

  @doc """
  Creates a registration.

  ## Examples

      iex> create_registration(%{field: value})
      {:ok, %Registration{}}

      iex> create_registration(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_registration(attrs \\ %{}) do
    %Registration{}
    |> Registration.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a registration.

  ## Examples

      iex> update_registration(registration, %{field: new_value})
      {:ok, %Registration{}}

      iex> update_registration(registration, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_registration(%Registration{} = registration, attrs) do
    registration
    |> Registration.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a registration.

  ## Examples

      iex> delete_registration(registration)
      {:ok, %Registration{}}

      iex> delete_registration(registration)
      {:error, %Ecto.Changeset{}}

  """
  def delete_registration(%Registration{} = registration) do
    Repo.delete(registration)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking registration changes.

  ## Examples

      iex> change_registration(registration)
      %Ecto.Changeset{data: %Registration{}}

  """
  def change_registration(%Registration{} = registration, attrs \\ %{}) do
    Registration.changeset(registration, attrs)
  end

  @doc """
  Lists registrations from the registrations_view with optional filtering.

  ## Options

    * `:season_id` - Filter by season ID
    * `:club_id` - Filter by user club ID (for club admins)
    * `:include_unenrolled` - Include unenrolled registrations (default: false)

  ## Examples

      iex> list_registrations_view(season_id: 1)
      [%RegistrationView{}, ...]

      iex> list_registrations_view(season_id: 1, club_id: 5)
      [%RegistrationView{}, ...]

  """
  def list_registrations_view(opts \\ []) do
    season_id = Keyword.get(opts, :season_id)
    club_id = Keyword.get(opts, :club_id)
    include_unenrolled = Keyword.get(opts, :include_unenrolled, false)

    query = from(r in RegistrationView)

    query =
      if season_id do
        from(r in query, where: r.season_id == ^season_id)
      else
        query
      end

    query =
      if club_id do
        from(r in query, where: r.user_club_id == ^club_id)
      else
        query
      end

    query =
      if not include_unenrolled do
        from(r in query, where: is_nil(r.unenrolled_at))
      else
        query
      end

    query =
      from(r in query,
        order_by: [asc: r.user_last_name, asc: r.user_first_name, asc: r.course_date]
      )

    Repo.all(query)
  end

  @doc """
  Signs out (unenrolls) a user from a course.

  ## Examples

      iex> sign_out(course_id, user_id, admin_user_id)
      {:ok, %Registration{}}

      iex> sign_out(invalid_course_id, user_id, admin_user_id)
      {:error, :not_found}

  """
  def sign_out(course_id, user_id, unenrolled_by_user_id) do
    query =
      from(r in Registration,
        where: r.course_id == ^course_id and r.user_id == ^user_id and is_nil(r.unenrolled_at)
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      registration ->
        registration
        |> Registration.changeset(%{
          unenrolled_at: Whistle.Timezone.now_local() |> NaiveDateTime.truncate(:second),
          unenrolled_by: unenrolled_by_user_id
        })
        |> Repo.update()
    end
  end

  @doc """
  Returns the list of active registrations for the given course.

  ## Examples

      iex> registrations_for_course(course)
      [%RegistrationView{}, ...]

  """
  def registrations_for_course(course) when is_struct(course) do
    query =
      from r in RegistrationView,
        where: r.course_id == ^course.id and is_nil(r.unenrolled_at)

    Repo.all(query)
  end

  defp active_online_registration(registration_id, user_id) do
    query =
      from r in Registration,
        join: c in Course,
        on: c.id == r.course_id,
        where:
          r.id == ^registration_id and r.user_id == ^user_id and is_nil(r.unenrolled_at) and
            c.online == true,
        select: {r, c}

    case Repo.one(query) do
      nil -> {:error, :not_found}
      registration -> {:ok, registration}
    end
  end

  defp current_date_ids_by_kind(registration_id) do
    selections =
      Repo.all(
        from s in CourseDateSelection,
          join: d in CourseDate,
          on: d.id == s.course_date_id,
          where: s.registration_id == ^registration_id,
          select: {d.kind, d.id}
      )

    {:ok, Map.new(selections, fn {kind, date_id} -> {Atom.to_string(kind), date_id} end)}
  end

  defp merge_date_ids_by_kind(current_date_ids, date_ids_by_kind) do
    normalized =
      Enum.reduce_while(date_ids_by_kind, %{}, fn {kind, date_id}, acc ->
        with {:ok, normalized_kind} <- normalize_date_kind(kind),
             {:ok, normalized_id} <- normalize_date_id(date_id) do
          {:cont, Map.put(acc, normalized_kind, normalized_id)}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case normalized do
      {:error, _} = error ->
        error

      normalized_map ->
        {:ok, Map.merge(current_date_ids, normalized_map)}
    end
  end

  defp normalize_date_kind(kind) when kind in [:mandatory, "mandatory"], do: {:ok, "mandatory"}
  defp normalize_date_kind(kind) when kind in [:elective, "elective"], do: {:ok, "elective"}
  defp normalize_date_kind(_kind), do: {:error, {:invalid_selection, :unknown_kind}}

  defp normalize_date_id(date_id) when is_integer(date_id), do: {:ok, date_id}

  defp normalize_date_id(date_id) when is_binary(date_id) do
    case Integer.parse(date_id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_selection, :invalid_date_id}}
    end
  end

  defp normalize_date_id(_date_id), do: {:error, {:invalid_selection, :invalid_date_id}}
end
