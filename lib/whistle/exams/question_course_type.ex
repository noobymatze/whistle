defmodule Whistle.Exams.QuestionCourseType do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_course_types ~w(F J G)

  schema "question_course_types" do
    field :question_id, :id
    field :course_type, :string

    field :created_at, :naive_datetime
  end

  def valid_course_types, do: @valid_course_types

  @doc false
  def changeset(qct, attrs) do
    qct
    |> cast(attrs, [:question_id, :course_type])
    |> validate_required([:question_id, :course_type])
    |> validate_inclusion(:course_type, @valid_course_types)
    |> unique_constraint([:question_id, :course_type])
  end
end
