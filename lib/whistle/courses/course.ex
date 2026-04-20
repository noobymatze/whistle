defmodule Whistle.Courses.Course do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Whistle.Repo
  alias Whistle.Courses.CourseDate
  alias Whistle.Courses.CourseDateTopic

  schema "courses" do
    field :name, :string
    field :type, :string
    field :date, :date
    field :online, :boolean, default: false
    field :max_participants, :integer
    field :max_per_club, :integer
    field :max_organizer_participants, :integer
    field :released_at, :naive_datetime
    field :organizer_id, :id
    field :season_id, :id

    has_many :course_dates, CourseDate
    has_many :course_date_topics, CourseDateTopic

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def available_types() do
    [
      {"F", "F"},
      {"J", "J"},
      {"G", "G"}
    ]
  end

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :name,
      :date,
      :online,
      :max_participants,
      :max_per_club,
      :max_organizer_participants,
      :released_at,
      :organizer_id,
      :season_id,
      :type
    ])
    |> validate_required([:name, :type, :season_id])
    |> validate_date_or_online()
    |> prevent_unsetting_online()
  end

  defp validate_date_or_online(changeset) do
    online = get_field(changeset, :online)
    date = get_field(changeset, :date)

    cond do
      online == true and not is_nil(date) ->
        add_error(changeset, :date, "must be blank when online is true")

      online == false and is_nil(date) ->
        add_error(changeset, :date, "can't be blank")

      true ->
        changeset
    end
  end

  # Prevent flipping online back to false once course_dates exist.
  defp prevent_unsetting_online(changeset) do
    if get_change(changeset, :online) == false and
         changeset.data.online == true and
         not is_nil(changeset.data.id) and
         Repo.exists?(from d in CourseDate, where: d.course_id == ^changeset.data.id) do
      add_error(changeset, :online, "cannot be unset while course dates exist")
    else
      changeset
    end
  end
end
