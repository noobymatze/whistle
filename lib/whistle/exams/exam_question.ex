defmodule Whistle.Exams.ExamQuestion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_questions" do
    field :exam_id, :id
    field :source_question_id, :id
    field :position, :integer
    field :type, :string
    field :difficulty, :string
    field :body_markdown, :string
    field :explanation_markdown, :string
    field :scoring_mode, :string
    field :points, :decimal, default: 1

    has_many :choices, Whistle.Exams.ExamQuestionChoice,
      foreign_key: :exam_question_id,
      preload_order: [asc: :position]

    field :created_at, :naive_datetime
  end

  @doc false
  def changeset(eq, attrs) do
    eq
    |> cast(attrs, [
      :exam_id,
      :source_question_id,
      :position,
      :type,
      :difficulty,
      :body_markdown,
      :explanation_markdown,
      :scoring_mode,
      :points,
      :created_at
    ])
    |> validate_required([:exam_id, :position, :type, :difficulty, :body_markdown, :points])
    |> validate_number(:position, greater_than_or_equal_to: 1)
    |> validate_number(:points, greater_than_or_equal_to: 0)
  end
end
