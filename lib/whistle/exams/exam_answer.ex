defmodule Whistle.Exams.ExamAnswer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_answers" do
    field :exam_id, :id
    field :exam_participant_id, :id
    field :exam_question_id, :id
    field :user_id, :id
    field :question_type, :string
    field :text_answer, :string
    field :is_correct, :boolean
    field :awarded_points, :decimal
    field :answered_at, :naive_datetime

    has_many :answer_choices, Whistle.Exams.ExamAnswerChoice, foreign_key: :exam_answer_id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @doc false
  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [
      :exam_id,
      :exam_participant_id,
      :exam_question_id,
      :user_id,
      :question_type,
      :text_answer,
      :is_correct,
      :awarded_points,
      :answered_at
    ])
    |> validate_required([
      :exam_id,
      :exam_participant_id,
      :exam_question_id,
      :user_id,
      :question_type,
      :answered_at
    ])
    |> unique_constraint([:exam_participant_id, :exam_question_id])
  end
end
