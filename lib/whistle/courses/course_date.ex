defmodule Whistle.Courses.CourseDate do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Whistle.Repo
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
    |> validate_topic_presence()
    |> validate_topic_belongs_to_course()
  end

  defp validate_topic_presence(changeset) do
    case get_field(changeset, :kind) do
      :elective -> validate_required(changeset, [:course_date_topic_id])
      :mandatory -> put_change(changeset, :course_date_topic_id, nil)
      _ -> changeset
    end
  end

  defp validate_topic_belongs_to_course(changeset) do
    topic_id = get_field(changeset, :course_date_topic_id)
    course_id = get_field(changeset, :course_id)

    if topic_id && course_id do
      topic = Repo.one(from t in CourseDateTopic, where: t.id == ^topic_id)

      if is_nil(topic) or topic.course_id != course_id do
        add_error(changeset, :course_date_topic_id, "does not belong to this course")
      else
        changeset
      end
    else
      changeset
    end
  end
end
