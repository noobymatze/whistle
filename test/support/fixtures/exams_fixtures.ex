defmodule Whistle.ExamsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Whistle.Exams` context.
  """

  alias Whistle.Exams

  @doc """
  Creates an active question with choices for the given course type and difficulty.
  """
  def question_fixture(attrs \\ %{}) do
    {:ok, question} =
      attrs
      |> Enum.into(%{
        type: "single_choice",
        difficulty: "low",
        body_markdown: "Was ist Abseits?",
        status: "active",
        scoring_mode: "exact_match"
      })
      |> Exams.create_question()

    question
  end

  @doc """
  Creates a question with two choices (one correct) and assigns it to a course type.
  """
  def question_with_choices_fixture(course_type, difficulty \\ "low") do
    question = question_fixture(%{difficulty: difficulty, status: "active"})

    {:ok, _} =
      Exams.create_question_choice(%{
        question_id: question.id,
        body_markdown: "Richtige Antwort",
        position: 1,
        is_correct: true
      })

    {:ok, _} =
      Exams.create_question_choice(%{
        question_id: question.id,
        body_markdown: "Falsche Antwort",
        position: 2,
        is_correct: false
      })

    Exams.set_question_course_types(question, [course_type])

    Exams.get_question_with_details!(question.id)
  end

  @doc """
  Populates enough questions for a full exam for the given course type.

  Uses default distribution (50/30/20 for low/medium/high with 20 questions):
  - 10 low, 6 medium, 4 high
  """
  def seed_questions_for_course_type(course_type, question_count \\ 20) do
    distribution = %{low_percentage: 50, medium_percentage: 30, high_percentage: 20}
    dist = struct(Whistle.Exams.CourseTypeQuestionDistribution, distribution)
    counts = Exams.calculate_difficulty_counts(question_count, dist)

    for _ <- 1..counts.low, do: question_with_choices_fixture(course_type, "low")
    for _ <- 1..counts.medium, do: question_with_choices_fixture(course_type, "medium")
    for _ <- 1..counts.high, do: question_with_choices_fixture(course_type, "high")

    :ok
  end
end
