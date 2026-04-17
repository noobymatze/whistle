defmodule Whistle.Courses.CourseDate do
  use Ecto.Schema
  import Ecto.Changeset

  alias Whistle.Courses.CourseDateTopic

  schema "course_dates" do
    field :date, :date
    field :time, :time
    field :kind, Ecto.Enum, values: [:mandatory, :elective]
    field :course_id, :id
    field :course_date_topic_id, :id

    belongs_to :topic, CourseDateTopic, foreign_key: :course_date_topic_id, define_field: false

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(course_date, attrs) do
    course_date
    |> cast(attrs, [:date, :time, :kind, :course_id, :course_date_topic_id])
    |> validate_required([:date, :time, :kind, :course_id])
    |> validate_topic_for_elective()
  end

  defp validate_topic_for_elective(changeset) do
    if get_field(changeset, :kind) == :elective do
      validate_required(changeset, [:course_date_topic_id])
    else
      changeset
    end
  end
end
