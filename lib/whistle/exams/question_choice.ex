defmodule Whistle.Exams.QuestionChoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "question_choices" do
    field :question_id, :id
    field :body_markdown, :string
    field :position, :integer
    field :is_correct, :boolean, default: false

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @doc false
  def changeset(choice, attrs) do
    choice
    |> cast(attrs, [:question_id, :body_markdown, :position, :is_correct])
    |> validate_required([:question_id, :body_markdown, :position])
  end
end
