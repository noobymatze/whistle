defmodule Whistle.Exams.ExamQuestionChoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_question_choices" do
    field :exam_question_id, :id
    field :source_question_choice_id, :id
    field :body_markdown, :string
    field :position, :integer
    field :is_correct, :boolean, default: false

    field :created_at, :naive_datetime
  end

  @doc false
  def changeset(eqc, attrs) do
    eqc
    |> cast(attrs, [
      :exam_question_id,
      :source_question_choice_id,
      :body_markdown,
      :position,
      :is_correct,
      :created_at
    ])
    |> validate_required([:exam_question_id, :body_markdown, :position])
  end
end
