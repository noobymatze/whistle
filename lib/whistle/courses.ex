defmodule Whistle.Courses do
  @moduledoc """
  The Courses context.
  """

  import Ecto.Query, warn: false
  alias Whistle.Repo

  alias Whistle.Courses.Course
  alias Whistle.Courses.CourseView

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
      released_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    )
    |> Repo.update()
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
