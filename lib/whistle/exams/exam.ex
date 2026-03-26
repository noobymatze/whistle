defmodule Whistle.Exams.Exam do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_states ~w(waiting_room running paused finished canceled)

  schema "exams" do
    field :course_id, :id
    field :course_type, :string
    field :state, :string, default: "waiting_room"
    field :question_count, :integer
    field :duration_seconds, :integer
    field :pass_percentage, :integer
    field :show_countdown_to_participants, :boolean, default: false
    field :started_at, :naive_datetime
    field :paused_at, :naive_datetime
    field :ended_at, :naive_datetime
    field :remaining_seconds, :integer
    field :created_by, :id

    has_many :participants, Whistle.Exams.ExamParticipant, foreign_key: :exam_id
    has_many :questions, Whistle.Exams.ExamQuestion, foreign_key: :exam_id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def valid_states, do: @valid_states

  @doc false
  def changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :course_id,
      :course_type,
      :state,
      :question_count,
      :duration_seconds,
      :pass_percentage,
      :show_countdown_to_participants,
      :started_at,
      :paused_at,
      :ended_at,
      :remaining_seconds,
      :created_by
    ])
    |> validate_required([
      :course_id,
      :course_type,
      :state,
      :question_count,
      :duration_seconds,
      :pass_percentage
    ])
    |> validate_inclusion(:state, @valid_states)
    |> validate_number(:question_count, greater_than: 0)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_number(:pass_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
