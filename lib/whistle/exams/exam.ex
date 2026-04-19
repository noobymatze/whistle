defmodule Whistle.Exams.Exam do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_states ~w(waiting_room running paused finished canceled)
  @valid_execution_modes ~w(synchronous asynchronous)

  schema "exams" do
    field :course_id, :id
    field :course_type, :string
    field :state, :string, default: "waiting_room"
    field :execution_mode, :string, default: "synchronous"
    field :question_count, :integer
    field :duration_seconds, :integer
    field :show_countdown_to_participants, :boolean, default: false
    field :started_at, :naive_datetime
    field :paused_at, :naive_datetime
    field :ended_at, :naive_datetime
    field :remaining_seconds, :integer
    field :created_by, :id

    # Threshold snapshot (from distribution at exam creation time)
    # F-course: l1/l2/l3 bands; G-course: pass_threshold
    field :l1_threshold, :integer
    field :l2_threshold, :integer
    field :l3_threshold, :integer
    field :pass_threshold, :integer

    has_many :participants, Whistle.Exams.ExamParticipant, foreign_key: :exam_id
    has_many :questions, Whistle.Exams.ExamQuestion, foreign_key: :exam_id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def valid_states, do: @valid_states
  def valid_execution_modes, do: @valid_execution_modes

  @doc false
  def changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :course_id,
      :course_type,
      :state,
      :execution_mode,
      :question_count,
      :duration_seconds,
      :show_countdown_to_participants,
      :started_at,
      :paused_at,
      :ended_at,
      :remaining_seconds,
      :created_by,
      :l1_threshold,
      :l2_threshold,
      :l3_threshold,
      :pass_threshold
    ])
    |> validate_required([
      :course_id,
      :course_type,
      :state,
      :question_count,
      :duration_seconds
    ])
    |> validate_inclusion(:state, @valid_states)
    |> validate_inclusion(:execution_mode, @valid_execution_modes)
    |> validate_number(:question_count, greater_than: 0)
    |> validate_number(:duration_seconds, greater_than: 0)
  end
end
