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
  alias Whistle.Accounts.User
  alias __MODULE__.Register

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
  def enroll_one(user, course, registered_by_user_id \\ nil) do
    Repo.transaction(fn ->
      # Lock the course to prevent concurrent registrations from exceeding capacity
      _locked_course = Courses.get_and_lock_course(course.id)

      cond do
        not Register.seat_available?(user, course, registrations_for_course(course)) ->
          Repo.rollback({:not_available, course})

        not Register.allowed?(user, course) ->
          Repo.rollback({:not_allowed, course})

        true ->
          # Check if there's an unenrolled registration to reactivate
          case find_unenrolled_registration(user.id, course.id) do
            nil ->
              # Create new registration
              attrs = %{
                user_id: user.id,
                course_id: course.id,
                registered_by: registered_by_user_id
              }

              case create_registration(attrs) do
                {:ok, registration} -> registration
                {:error, changeset} -> Repo.rollback(changeset)
              end

            unenrolled_registration ->
              # Reactivate existing registration
              case reenroll_registration(unenrolled_registration) do
                {:ok, registration} -> registration
                {:error, changeset} -> Repo.rollback(changeset)
              end
          end
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
          unenrolled_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
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

  defmodule Register do
    @moduledoc """
    Business logic for validating course registrations.
    """

    import Ecto.Query, warn: false
    alias Whistle.Repo
    alias Whistle.Registrations.Registration
    alias Whistle.Courses
    alias Whistle.Courses.Course
    alias Whistle.Accounts.User

    @doc """
    Check if a seat is available for the user for the given course.

    This accounts for:
    - Organizer vs non-organizer limits
    - Course release status
    - Per-club limits
    """
    def seat_available?(%User{} = user, course, course_registrations) when is_struct(course) do
      {from_organizer, others} = group_by_organizer(course_registrations, course)

      from_organizer_and_allowed? =
        user.club_id == course.organizer_id &&
          length(from_organizer) < course.max_organizer_participants &&
          course.max_organizer_participants > 0

      # Calculate max available spots for non-organizers
      max =
        course.max_participants -
          if course.released_at do
            length(from_organizer)
          else
            course.max_organizer_participants
          end

      # Check per-club limit for non-organizers
      others_by_club = Enum.group_by(others, & &1.user_club_id)
      user_club_count = length(Map.get(others_by_club, user.club_id, []))

      from_others_and_allowed? =
        user.club_id != course.organizer_id &&
          length(others) < max &&
          max > 0 &&
          user_club_count < course.max_per_club

      from_others_and_allowed? or from_organizer_and_allowed?
    end

    @doc """
    Check if the user is allowed to participate in the given course.

    Rules:
      1. User has not exceeded the 2-course limit for the season
      2. User is not already registered for this specific course
    """
    def allowed?(%User{} = user, course) when is_struct(course) do
      query =
        from r in Registration,
          join: c in Course,
          on: c.id == r.course_id,
          where:
            r.user_id == ^user.id and c.season_id == ^course.season_id and is_nil(r.unenrolled_at)

      registrations = Repo.all(query)

      # Check 2-course limit
      if length(registrations) >= 2 do
        false
      else
        # Check if already registered for this specific course
        not Enum.any?(registrations, fn r -> r.course_id == course.id end)
      end
    end

    defp group_by_organizer(course_registrations, %Course{} = course) do
      result =
        course_registrations
        |> Enum.group_by(fn r -> r.user_club_id == course.organizer_id end)

      {Map.get(result, true, []), Map.get(result, false, [])}
    end
  end
end
