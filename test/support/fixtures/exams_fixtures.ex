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

  @doc """
  Creates a draft exam variant.
  """
  def exam_variant_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "F1",
        course_type: "F",
        status: "draft",
        duration_seconds: 1800,
        l3_threshold: 12,
        l2_threshold: 15,
        l1_threshold: 18
      })

    {:ok, variant} = Exams.create_exam_variant(attrs)
    variant
  end

  @doc """
  Creates an enabled exam variant with active questions.
  """
  def enabled_exam_variant_fixture(course_type \\ "F", question_count \\ 3) do
    thresholds =
      case course_type do
        "F" -> %{l3_threshold: 1, l2_threshold: 2, l1_threshold: 3}
        "G" -> %{pass_threshold: 1}
        _ -> %{}
      end

    variant =
      exam_variant_fixture(
        Map.merge(
          %{
            name: "#{course_type}1",
            course_type: course_type,
            status: "draft",
            duration_seconds: 1800,
            l1_threshold: nil,
            l2_threshold: nil,
            l3_threshold: nil,
            pass_threshold: nil
          },
          thresholds
        )
      )

    questions =
      for _ <- 1..question_count do
        question_with_choices_fixture(course_type, "low")
      end

    question_positions =
      questions
      |> Enum.with_index(1)
      |> Enum.map(fn {question, position} -> {question.id, position} end)

    {:ok, _variant} = Exams.set_exam_variant_questions(variant, question_positions)
    {:ok, variant} = Exams.update_exam_variant(variant, %{status: "enabled"})
    Exams.get_exam_variant_with_questions!(variant.id)
  end
end
