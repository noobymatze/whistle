defmodule Whistle.Exams.ExamAnswerChoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_answer_choices" do
    field :exam_answer_id, :id
    field :exam_question_choice_id, :id

    field :created_at, :naive_datetime
  end

  @doc false
  def changeset(eac, attrs) do
    eac
    |> cast(attrs, [:exam_answer_id, :exam_question_choice_id, :created_at])
    |> validate_required([:exam_answer_id, :exam_question_choice_id])
    |> unique_constraint([:exam_answer_id, :exam_question_choice_id])
  end
end
