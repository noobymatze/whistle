defmodule Whistle.Exams.Scoring do
  @moduledoc """
  Pure scoring logic for exam answers.

  Supports:
  - `single_choice` with `exact_match` (correct iff exactly the right choice is selected)
  - `multiple_choice` with `exact_match` (correct iff the selected set equals the correct set)
  - `multiple_choice` with `partial_credit` using the formula:
      score = max(0, correct_selected/total_correct - wrong_selected/total_wrong)
  """

  alias Whistle.Exams.ExamQuestion

  @doc """
  Scores a single answer for the given question snapshot and selected choice IDs.

  Returns `{awarded_points, is_correct}` where awarded_points is a float in [0, max_points].
  """
  def score_answer(%ExamQuestion{} = question, selected_choice_ids)
      when is_list(selected_choice_ids) do
    selected = MapSet.new(selected_choice_ids)
    correct_ids = MapSet.new(Enum.filter(question.choices, & &1.is_correct), & &1.id)
    wrong_ids = MapSet.new(Enum.reject(question.choices, & &1.is_correct), & &1.id)
    max_points = Decimal.to_float(question.points)

    scoring_mode = question.scoring_mode || "exact_match"

    case {question.type, scoring_mode} do
      {"single_choice", _} ->
        # Exactly the one correct choice must be selected
        is_correct = MapSet.equal?(selected, correct_ids)
        awarded = if is_correct, do: max_points, else: 0.0
        {awarded, is_correct}

      {"multiple_choice", "exact_match"} ->
        is_correct = MapSet.equal?(selected, correct_ids)
        awarded = if is_correct, do: max_points, else: 0.0
        {awarded, is_correct}

      {"multiple_choice", "partial_credit"} ->
        total_correct = MapSet.size(correct_ids)
        total_wrong = MapSet.size(wrong_ids)

        correct_selected = MapSet.intersection(selected, correct_ids) |> MapSet.size()
        wrong_selected = MapSet.intersection(selected, wrong_ids) |> MapSet.size()

        raw =
          cond do
            total_correct == 0 ->
              0.0

            total_wrong == 0 ->
              correct_selected / total_correct

            true ->
              correct_selected / total_correct - wrong_selected / total_wrong
          end

        awarded = max(0.0, raw) * max_points
        is_correct = awarded > 0
        {awarded, is_correct}

      _ ->
        {0.0, false}
    end
  end

  @doc """
  Computes the total score across all questions for a participant.

  Takes a list of `{exam_question, selected_choice_ids}` pairs.
  Returns `%{score: float, max_score: float, passed: boolean}` given a pass_percentage.
  """
  def compute_total(question_answer_pairs, pass_percentage) do
    {score, max_score} =
      Enum.reduce(question_answer_pairs, {0.0, 0.0}, fn {question, choice_ids}, {s, m} ->
        {awarded, _correct} = score_answer(question, choice_ids)
        {s + awarded, m + Decimal.to_float(question.points)}
      end)

    percentage = if max_score > 0, do: score / max_score * 100, else: 0.0
    passed = percentage >= pass_percentage

    %{score: score, max_score: max_score, passed: passed, percentage: percentage}
  end
end
