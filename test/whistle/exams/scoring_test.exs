defmodule Whistle.Exams.ScoringTest do
  use ExUnit.Case, async: true

  alias Whistle.Exams.{ExamQuestion, ExamQuestionChoice, Scoring}

  defp build_question(type, scoring_mode, points, choices) do
    choice_structs =
      Enum.with_index(choices, 1)
      |> Enum.map(fn {{body, is_correct}, i} ->
        %ExamQuestionChoice{
          id: i,
          exam_question_id: 1,
          body_markdown: body,
          position: i,
          is_correct: is_correct
        }
      end)

    %ExamQuestion{
      id: 1,
      type: type,
      scoring_mode: scoring_mode,
      points: Decimal.new(points),
      choices: choice_structs
    }
  end

  describe "score_answer/2 single_choice" do
    test "correct single choice returns full points" do
      q = build_question("single_choice", "exact_match", "1", [{"A", true}, {"B", false}])
      assert {1.0, true} = Scoring.score_answer(q, [1])
    end

    test "wrong single choice returns 0 points" do
      q = build_question("single_choice", "exact_match", "1", [{"A", true}, {"B", false}])
      assert {pts, false} = Scoring.score_answer(q, [2])
      assert pts == 0
    end

    test "empty selection returns 0 points" do
      q = build_question("single_choice", "exact_match", "1", [{"A", true}, {"B", false}])
      assert {pts, false} = Scoring.score_answer(q, [])
      assert pts == 0
    end

    test "multiple selections returns 0 points for single_choice" do
      q = build_question("single_choice", "exact_match", "1", [{"A", true}, {"B", false}])
      assert {pts, false} = Scoring.score_answer(q, [1, 2])
      assert pts == 0
    end
  end

  describe "score_answer/2 multiple_choice exact_match" do
    test "selects all correct choices returns full points" do
      q =
        build_question("multiple_choice", "exact_match", "2", [
          {"A", true},
          {"B", true},
          {"C", false}
        ])

      assert {2.0, true} = Scoring.score_answer(q, [1, 2])
    end

    test "partial selection returns 0 for exact_match" do
      q =
        build_question("multiple_choice", "exact_match", "2", [
          {"A", true},
          {"B", true},
          {"C", false}
        ])

      assert {pts, false} = Scoring.score_answer(q, [1])
      assert pts == 0
    end

    test "wrong selection returns 0 for exact_match" do
      q =
        build_question("multiple_choice", "exact_match", "2", [
          {"A", true},
          {"B", true},
          {"C", false}
        ])

      assert {pts, false} = Scoring.score_answer(q, [3])
      assert pts == 0
    end
  end

  describe "score_answer/2 multiple_choice partial_credit" do
    test "all correct, no wrong returns full points" do
      q =
        build_question("multiple_choice", "partial_credit", "2", [
          {"A", true},
          {"B", true},
          {"C", false},
          {"D", false}
        ])

      {awarded, is_correct} = Scoring.score_answer(q, [1, 2])
      assert_in_delta awarded, 2.0, 0.001
      assert is_correct
    end

    test "half correct, no wrong returns half points" do
      q =
        build_question("multiple_choice", "partial_credit", "2", [
          {"A", true},
          {"B", true},
          {"C", false},
          {"D", false}
        ])

      {awarded, _} = Scoring.score_answer(q, [1])
      assert_in_delta awarded, 1.0, 0.001
    end

    test "one wrong reduces score" do
      q =
        build_question("multiple_choice", "partial_credit", "2", [
          {"A", true},
          {"B", true},
          {"C", false},
          {"D", false}
        ])

      # 2/2 correct - 1/2 wrong = 0.5 * 2 = 1.0
      {awarded, _} = Scoring.score_answer(q, [1, 2, 3])
      assert_in_delta awarded, 1.0, 0.001
    end

    test "all wrong returns 0" do
      q =
        build_question("multiple_choice", "partial_credit", "2", [
          {"A", true},
          {"B", true},
          {"C", false},
          {"D", false}
        ])

      {awarded, is_correct} = Scoring.score_answer(q, [3, 4])
      assert awarded == 0.0
      refute is_correct
    end
  end

  describe "compute_total/2" do
    test "sums scores across questions" do
      q1 = build_question("single_choice", "exact_match", "1", [{"A", true}, {"B", false}])
      q2 = build_question("single_choice", "exact_match", "1", [{"C", true}, {"D", false}])

      # q1 correct (id 1), q2 wrong (id 3 which doesn't exist)
      result = Scoring.compute_total([{q1, [1]}, {q2, [4]}], 60)

      assert_in_delta result.score, 1.0, 0.001
      assert_in_delta result.max_score, 2.0, 0.001
    end

    test "passed is true when percentage >= pass_percentage" do
      q = build_question("single_choice", "exact_match", "1", [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], 100)
      assert result.passed
    end

    test "passed is false when percentage < pass_percentage" do
      q = build_question("single_choice", "exact_match", "1", [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, []}], 60)
      refute result.passed
    end

    test "returns percentage" do
      q = build_question("single_choice", "exact_match", "2", [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], 50)
      assert_in_delta result.percentage, 100.0, 0.001
    end

    test "handles empty question list" do
      result = Scoring.compute_total([], 60)
      assert result.score == 0.0
      assert result.max_score == 0.0
      refute result.passed
    end
  end
end
