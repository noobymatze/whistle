defmodule Whistle.Courses.CourseDateTopic do
  use Ecto.Schema
  import Ecto.Changeset

  alias Whistle.Courses.CourseDate

  schema "course_date_topics" do
    field :name, :string
    field :course_id, :id

    has_many :course_dates, CourseDate, foreign_key: :course_date_topic_id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:name, :course_id])
    |> validate_required([:name, :course_id])
  end
end
