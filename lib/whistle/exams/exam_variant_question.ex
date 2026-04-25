defmodule Whistle.Exams.ExamVariantQuestion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_variant_questions" do
    field :position, :integer

    belongs_to :exam_variant, Whistle.Exams.ExamVariant
    belongs_to :question, Whistle.Exams.Question

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @doc false
  def changeset(variant_question, attrs) do
    variant_question
    |> cast(attrs, [:exam_variant_id, :question_id, :position])
    |> validate_required([:exam_variant_id, :question_id, :position])
    |> validate_number(:position, greater_than_or_equal_to: 1)
    |> unique_constraint([:exam_variant_id, :question_id])
    |> unique_constraint([:exam_variant_id, :position])
    |> foreign_key_constraint(:question_id)
  end
end
