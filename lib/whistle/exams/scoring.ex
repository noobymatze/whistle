defmodule Whistle.Exams.Scoring do
  @moduledoc """
  Pure scoring logic for referee exam answers.

  For online referee exams, scoring is full-or-zero only:
  - `single_choice`: full points if exactly the one correct choice is selected, else 0
  - `multiple_choice`: full points if the selected set exactly equals the correct set, else 0

  Point values are integers (1, 2, or 3) stored on the exam question snapshot.
  """

  alias Whistle.Exams.ExamQuestion

  @doc """
  Scores a single answer for the given question snapshot and selected choice IDs.

  Returns `{awarded_points, is_correct}` where awarded_points is an integer.
  Full points are awarded only if the selection exactly matches all correct choices.
  """
  def score_answer(%ExamQuestion{} = question, selected_choice_ids)
      when is_list(selected_choice_ids) do
    selected = MapSet.new(selected_choice_ids)
    correct_ids = MapSet.new(Enum.filter(question.choices, & &1.is_correct), & &1.id)
    max_points = question.points

    case question.type do
      type when type in ["single_choice", "multiple_choice"] ->
        is_correct = MapSet.equal?(selected, correct_ids)
        awarded = if is_correct, do: max_points, else: 0
        {awarded, is_correct}

      _ ->
        {0, false}
    end
  end

  @doc """
  Computes the total score across all questions for a participant.

  Takes a list of `{exam_question, selected_choice_ids}` pairs and an exam config map
  containing threshold fields (`course_type`, and the relevant threshold integers).

  Returns a structured result:
  ```
  %{
    achieved_points: integer,
    max_points: integer,
    outcome: :l1_eligible | :l2_pass | :l3_pass | :fail | :not_applicable
  }
  ```

  For F-course:
  - `>= l1_threshold` → `:l1_eligible` (triggers manual review)
  - `>= l2_threshold` → `:l2_pass`
  - `>= l3_threshold` → `:l3_pass`
  - else → `:fail`

  For G-course:
  - `>= pass_threshold` → `:l3_pass`
  - else → `:fail`

  For J-course (or unknown): → `:not_applicable`
  """
  def compute_total(question_answer_pairs, exam_config) do
    {achieved, max} =
      Enum.reduce(question_answer_pairs, {0, 0}, fn {question, choice_ids}, {s, m} ->
        {awarded, _correct} = score_answer(question, choice_ids)
        {s + awarded, m + question.points}
      end)

    outcome = determine_outcome(achieved, exam_config)

    %{achieved_points: achieved, max_points: max, outcome: outcome}
  end

  defp determine_outcome(_achieved_points, %{course_type: "J"}), do: :not_applicable
  defp determine_outcome(_achieved_points, %{course_type: nil}), do: :not_applicable

  defp determine_outcome(achieved, %{course_type: "F"} = config) do
    l1 = Map.get(config, :l1_threshold)
    l2 = Map.get(config, :l2_threshold)
    l3 = Map.get(config, :l3_threshold)

    cond do
      not is_nil(l1) and achieved >= l1 -> :l1_eligible
      not is_nil(l2) and achieved >= l2 -> :l2_pass
      not is_nil(l3) and achieved >= l3 -> :l3_pass
      true -> :fail
    end
  end

  defp determine_outcome(achieved, %{course_type: "G"} = config) do
    threshold = Map.get(config, :pass_threshold)

    if not is_nil(threshold) and achieved >= threshold do
      :l3_pass
    else
      :fail
    end
  end

  defp determine_outcome(_achieved, _config), do: :not_applicable
end
