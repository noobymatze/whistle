defmodule Whistle.Courses do
  @moduledoc """
  The Courses context.
  """

  import Ecto.Query, warn: false
  alias Whistle.Repo

  alias Whistle.Courses.Course
  alias Whistle.Courses.CourseDate
  alias Whistle.Courses.CourseDateTopic
  alias Whistle.Courses.CourseDateSelection
  alias Whistle.Courses.CourseView
  alias Whistle.Registrations.Registration

  @doc """
  Returns the list of courses.

  ## Examples

      iex> list_courses()
      [%Course{}, ...]

  """
  def list_courses do
    Repo.all(Course)
  end

  def list_courses_view(opts \\ []) do
    season_id = Keyword.get(opts, :season_id)

    query = from c in CourseView, order_by: [desc: c.date]

    query =
      if season_id do
        from c in query, where: c.season_id == ^season_id
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Returns the list of courses as a map.

  ## Examples

      iex> list_courses()
      [%Course{}, ...]

  """
  def get_courses_as_map() do
    list_courses()
    |> Map.new(fn course -> {course.id, course.name} end)
  end

  @doc """
  Gets a single course.

  Raises `Ecto.NoResultsError` if the Course does not exist.

  ## Examples

      iex> get_course!(123)
      %Course{}

      iex> get_course!(456)
      ** (Ecto.NoResultsError)

  """
  def get_course!(id), do: Repo.get!(Course, id)

  @doc """
  Gets a single course.

  Returns `nil` if the Course does not exist.
  """
  def get_course(id), do: Repo.get(Course, id)

  @doc """
  Creates a course.

  ## Examples

      iex> create_course(%{field: value})
      {:ok, %Course{}}

      iex> create_course(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_course(attrs \\ %{}) do
    %Course{}
    |> Course.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a course.

  ## Examples

      iex> update_course(course, %{field: new_value})
      {:ok, %Course{}}

      iex> update_course(course, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_course(%Course{} = course, attrs) do
    course
    |> Course.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a course.

  ## Examples

      iex> delete_course(course)
      {:ok, %Course{}}

      iex> delete_course(course)
      {:error, %Ecto.Changeset{}}

  """
  def delete_course(%Course{} = course) do
    Repo.delete(course)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking course changes.

  ## Examples

      iex> change_course(course)
      %Ecto.Changeset{data: %Course{}}

  """
  def change_course(%Course{} = course, attrs \\ %{}) do
    Course.changeset(course, attrs)
  end

  def list_course_dates(%Course{id: course_id}) do
    Repo.all(
      from d in CourseDate, where: d.course_id == ^course_id, order_by: [asc: d.date, asc: d.time]
    )
  end

  def list_course_dates_with_topics(%Course{id: course_id}) do
    query =
      from d in CourseDate,
        left_join: t in CourseDateTopic,
        on: t.id == d.course_date_topic_id,
        where: d.course_id == ^course_id,
        order_by: [asc: d.date, asc: d.time],
        preload: [topic: t]

    Repo.all(query)
  end

  def get_course_date!(id), do: Repo.get!(CourseDate, id)

  def create_course_date(attrs) do
    %CourseDate{}
    |> CourseDate.changeset(attrs)
    |> Repo.insert()
  end

  def update_course_date(%CourseDate{} = course_date, attrs) do
    course_date
    |> CourseDate.changeset(attrs)
    |> Repo.update()
  end

  def count_selections_for_date(%CourseDate{id: id}) do
    Repo.one(
      from s in CourseDateSelection,
        join: r in Whistle.Registrations.Registration,
        on: r.id == s.registration_id,
        where: s.course_date_id == ^id and is_nil(r.unenrolled_at),
        select: count(s.id)
    )
  end

  def count_selections_for_topic(%CourseDateTopic{id: id}) do
    Repo.one(
      from s in CourseDateSelection,
        join: d in CourseDate,
        on: d.id == s.course_date_id,
        join: r in Whistle.Registrations.Registration,
        on: r.id == s.registration_id,
        where: d.course_date_topic_id == ^id and is_nil(r.unenrolled_at),
        select: count(s.id)
    )
  end

  def list_date_availability(%Course{id: course_id, max_participants: max_participants}) do
    counts =
      from(d in CourseDate,
        left_join: s in CourseDateSelection,
        on: s.course_date_id == d.id,
        left_join: r in Registration,
        on: r.id == s.registration_id and is_nil(r.unenrolled_at),
        where: d.course_id == ^course_id,
        group_by: d.id,
        select: {d.id, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    counts
    |> Enum.map(fn {date_id, selected_count} ->
      remaining =
        if is_integer(max_participants) do
          max(max_participants - selected_count, 0)
        end

      {date_id, %{selected_count: selected_count, remaining: remaining}}
    end)
    |> Map.new()
  end

  def delete_course_date(%CourseDate{} = course_date) do
    Repo.delete(course_date)
  end

  def list_course_date_topics(%Course{id: course_id}) do
    Repo.all(from t in CourseDateTopic, where: t.course_id == ^course_id, order_by: [asc: t.name])
  end

  def get_course_date_topic!(id), do: Repo.get!(CourseDateTopic, id)

  def create_course_date_topic(attrs) do
    %CourseDateTopic{}
    |> CourseDateTopic.changeset(attrs)
    |> Repo.insert()
  end

  def update_course_date_topic(%CourseDateTopic{} = topic, attrs) do
    topic
    |> CourseDateTopic.changeset(attrs)
    |> Repo.update()
  end

  def delete_course_date_topic(%CourseDateTopic{} = topic) do
    Repo.delete(topic)
  end

  @doc """
  Releases a course by setting the released_at timestamp.

  ## Examples

      iex> release_course(course)
      {:ok, %Course{}}

      iex> release_course(course)
      {:error, %Ecto.Changeset{}}

  """
  def release_course(%Course{} = course) do
    course
    |> Ecto.Changeset.change(
      released_at: Whistle.Timezone.now_local() |> NaiveDateTime.truncate(:second)
    )
    |> Repo.update()
  end

  @doc """
  Releases detailed exam solutions for participants of a course.
  """
  def release_exam_solutions(%Course{} = course) do
    course
    |> Ecto.Changeset.change(
      exam_solutions_released_at: Whistle.Timezone.now_local() |> NaiveDateTime.truncate(:second)
    )
    |> Repo.update()
  end

  @doc """
  Hides detailed exam solutions for participants of a course.
  """
  def hide_exam_solutions(%Course{} = course) do
    course
    |> Ecto.Changeset.change(exam_solutions_released_at: nil)
    |> Repo.update()
  end

  @doc """
  Returns a map of registration_id => [CourseDate] for an online course.
  """
  def list_date_selections_for_registration(registration_id) do
    query =
      from s in CourseDateSelection,
        join: r in Registration,
        on: r.id == s.registration_id,
        join: d in CourseDate,
        on: d.id == s.course_date_id,
        left_join: t in CourseDateTopic,
        on: t.id == d.course_date_topic_id,
        where: s.registration_id == ^registration_id and is_nil(r.unenrolled_at),
        order_by: [asc: d.kind, asc: d.date, asc: d.time],
        select: %{date: d, topic: t}

    Repo.all(query)
  end

  def list_all_date_selections do
    query =
      from s in CourseDateSelection,
        join: r in Registration,
        on: r.id == s.registration_id,
        join: d in CourseDate,
        on: d.id == s.course_date_id,
        where: is_nil(r.unenrolled_at),
        select: {s.registration_id, d}

    query
    |> Repo.all()
    |> Enum.group_by(fn {reg_id, _} -> reg_id end, fn {_, date} -> date end)
  end

  def list_date_selections_for_course(%Course{id: course_id}) do
    query =
      from s in CourseDateSelection,
        join: r in Registration,
        on: r.id == s.registration_id,
        join: d in CourseDate,
        on: d.id == s.course_date_id,
        where: r.course_id == ^course_id and is_nil(r.unenrolled_at),
        select: {r.id, d}

    query
    |> Repo.all()
    |> Enum.group_by(fn {reg_id, _} -> reg_id end, fn {_, date} -> date end)
  end

  @doc """
  Gets and locks a course for the duration of a transaction.

  This uses SELECT FOR UPDATE to prevent race conditions during enrollment.
  The lock is automatically released at the end of the transaction.

  ## Examples

      iex> Repo.transaction(fn ->
      ...>   locked_course = Courses.get_and_lock_course(123)
      ...>   # ... perform enrollment logic
      ...> end)

  """
  def get_and_lock_course(course_id) do
    query =
      from c in Course,
        where: c.id == ^course_id,
        lock: "FOR UPDATE"

    Repo.one!(query)
  end
end
