defmodule Whistle.Exams.CourseTypeQuestionDistribution do
  use Ecto.Schema
  import Ecto.Changeset

  @default_low_percentage 50
  @default_medium_percentage 30
  @default_high_percentage 20
  @default_question_count 20
  @default_pass_percentage 75
  @default_duration_seconds 3600

  schema "course_type_question_distributions" do
    field :course_type, :string
    field :question_count, :integer, default: @default_question_count
    field :low_percentage, :integer, default: @default_low_percentage
    field :medium_percentage, :integer, default: @default_medium_percentage
    field :high_percentage, :integer, default: @default_high_percentage
    field :pass_percentage, :integer, default: @default_pass_percentage
    field :duration_seconds, :integer, default: @default_duration_seconds

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def defaults do
    %{
      low_percentage: @default_low_percentage,
      medium_percentage: @default_medium_percentage,
      high_percentage: @default_high_percentage,
      question_count: @default_question_count,
      pass_percentage: @default_pass_percentage,
      duration_seconds: @default_duration_seconds
    }
  end

  @doc false
  def changeset(dist, attrs) do
    dist
    |> cast(attrs, [
      :course_type,
      :question_count,
      :low_percentage,
      :medium_percentage,
      :high_percentage,
      :pass_percentage,
      :duration_seconds
    ])
    |> validate_required([
      :course_type,
      :question_count,
      :low_percentage,
      :medium_percentage,
      :high_percentage,
      :pass_percentage,
      :duration_seconds
    ])
    |> validate_number(:question_count, greater_than: 0)
    |> validate_number(:pass_percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_percentages_sum()
    |> unique_constraint(:course_type)
  end

  defp validate_percentages_sum(changeset) do
    low = get_field(changeset, :low_percentage) || 0
    medium = get_field(changeset, :medium_percentage) || 0
    high = get_field(changeset, :high_percentage) || 0

    if low + medium + high == 100 do
      changeset
    else
      add_error(changeset, :low_percentage, "Die Summe der Anteile muss 100 ergeben")
    end
  end
end
