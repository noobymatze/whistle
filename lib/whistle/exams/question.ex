defmodule Whistle.Exams.Question do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(single_choice multiple_choice text)
  @valid_difficulties ~w(low medium high)
  @valid_statuses ~w(draft active archived)
  @valid_scoring_modes ~w(exact_match partial_credit)

  schema "questions" do
    field :type, :string
    field :difficulty, :string
    field :body_markdown, :string
    field :explanation_markdown, :string
    field :status, :string, default: "draft"
    field :scoring_mode, :string
    field :nordref_reference, :string
    field :created_by, :id

    has_many :choices, Whistle.Exams.QuestionChoice,
      foreign_key: :question_id,
      preload_order: [asc: :position]

    has_many :course_type_assignments, Whistle.Exams.QuestionCourseType, foreign_key: :question_id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def valid_types, do: @valid_types
  def valid_difficulties, do: @valid_difficulties
  def valid_statuses, do: @valid_statuses
  def valid_scoring_modes, do: @valid_scoring_modes

  @doc false
  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :type,
      :difficulty,
      :body_markdown,
      :explanation_markdown,
      :status,
      :nordref_reference,
      :created_by
    ])
    |> validate_required([:type, :difficulty, :body_markdown, :status])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:difficulty, @valid_difficulties)
    |> validate_inclusion(:status, @valid_statuses)
    |> derive_scoring_mode()
  end

  defp derive_scoring_mode(changeset) do
    case get_field(changeset, :type) do
      "multiple_choice" ->
        put_change(changeset, :scoring_mode, "partial_credit")

      type when type in ["single_choice", "text"] ->
        put_change(changeset, :scoring_mode, "exact_match")

      _ ->
        changeset
    end
  end
end
