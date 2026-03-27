defmodule Whistle.Exams.ScoringTest do
  use ExUnit.Case, async: true

  alias Whistle.Exams.{ExamQuestion, ExamQuestionChoice, Scoring}

  defp build_question(type, points, choices) do
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
      scoring_mode: "exact_match",
      points: points,
      choices: choice_structs
    }
  end

  defp f_config(l3, l2, l1) do
    %{course_type: "F", l3_threshold: l3, l2_threshold: l2, l1_threshold: l1, pass_threshold: nil}
  end

  defp g_config(pass) do
    %{course_type: "G", l3_threshold: nil, l2_threshold: nil, l1_threshold: nil, pass_threshold: pass}
  end

  defp j_config do
    %{course_type: "J", l3_threshold: nil, l2_threshold: nil, l1_threshold: nil, pass_threshold: nil}
  end

  describe "score_answer/2 single_choice" do
    test "correct single choice returns full points" do
      q = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      assert {1, true} = Scoring.score_answer(q, [1])
    end

    test "wrong single choice returns 0 points" do
      q = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      assert {0, false} = Scoring.score_answer(q, [2])
    end

    test "empty selection returns 0 points" do
      q = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      assert {0, false} = Scoring.score_answer(q, [])
    end

    test "multiple selections returns 0 for single_choice" do
      q = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      assert {0, false} = Scoring.score_answer(q, [1, 2])
    end

    test "question with 2-point value awards 2 for correct answer" do
      q = build_question("single_choice", 2, [{"A", true}, {"B", false}])
      assert {2, true} = Scoring.score_answer(q, [1])
    end

    test "question with 3-point value awards 3 for correct answer" do
      q = build_question("single_choice", 3, [{"A", true}, {"B", false}])
      assert {3, true} = Scoring.score_answer(q, [1])
    end
  end

  describe "score_answer/2 multiple_choice" do
    test "selects all correct choices returns full points" do
      q = build_question("multiple_choice", 2, [{"A", true}, {"B", true}, {"C", false}])
      assert {2, true} = Scoring.score_answer(q, [1, 2])
    end

    test "partial selection returns 0 (no partial credit)" do
      q = build_question("multiple_choice", 2, [{"A", true}, {"B", true}, {"C", false}])
      assert {0, false} = Scoring.score_answer(q, [1])
    end

    test "wrong selection returns 0" do
      q = build_question("multiple_choice", 2, [{"A", true}, {"B", true}, {"C", false}])
      assert {0, false} = Scoring.score_answer(q, [3])
    end

    test "selecting correct plus wrong returns 0" do
      q = build_question("multiple_choice", 2, [{"A", true}, {"B", true}, {"C", false}])
      assert {0, false} = Scoring.score_answer(q, [1, 2, 3])
    end

    test "empty selection returns 0" do
      q = build_question("multiple_choice", 2, [{"A", true}, {"B", true}, {"C", false}])
      assert {0, false} = Scoring.score_answer(q, [])
    end
  end

  describe "compute_total/2 — F-course scoring" do
    test "sums points across questions" do
      q1 = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      q2 = build_question("single_choice", 2, [{"C", true}, {"D", false}])

      # q1 correct, q2 correct → 3 points
      result = Scoring.compute_total([{q1, [1]}, {q2, [1]}], f_config(10, 20, 28))
      assert result.achieved_points == 3
      assert result.max_points == 3
    end

    test "unanswered questions count as 0 points" do
      q1 = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      q2 = build_question("single_choice", 1, [{"C", true}, {"D", false}])

      # q2 not answered
      result = Scoring.compute_total([{q1, [1]}, {q2, []}], f_config(1, 2, 3))
      assert result.achieved_points == 1
      assert result.max_points == 2
    end

    test "outcome is :fail when below l3_threshold" do
      q = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [2]}], f_config(18, 24, 28))
      assert result.outcome == :fail
    end

    test "outcome is :l3_pass at l3_threshold boundary" do
      q = build_question("single_choice", 18, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], f_config(18, 24, 28))
      assert result.outcome == :l3_pass
    end

    test "outcome is :l2_pass at l2_threshold boundary" do
      q = build_question("single_choice", 24, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], f_config(18, 24, 28))
      assert result.outcome == :l2_pass
    end

    test "outcome is :l1_eligible at l1_threshold boundary" do
      q = build_question("single_choice", 28, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], f_config(18, 24, 28))
      assert result.outcome == :l1_eligible
    end

    test "outcome is :l1_eligible above l1_threshold" do
      q = build_question("single_choice", 30, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], f_config(18, 24, 28))
      assert result.outcome == :l1_eligible
    end

    test "handles empty question list" do
      result = Scoring.compute_total([], f_config(18, 24, 28))
      assert result.achieved_points == 0
      assert result.max_points == 0
      assert result.outcome == :fail
    end
  end

  describe "compute_total/2 — G-course scoring" do
    test "outcome is :fail when below pass_threshold" do
      q = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [2]}], g_config(14))
      assert result.outcome == :fail
    end

    test "outcome is :l3_pass at pass_threshold boundary" do
      q = build_question("single_choice", 14, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], g_config(14))
      assert result.outcome == :l3_pass
    end

    test "outcome is :l3_pass above pass_threshold" do
      q = build_question("single_choice", 20, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], g_config(14))
      assert result.outcome == :l3_pass
    end
  end

  describe "compute_total/2 — J-course scoring" do
    test "outcome is :not_applicable for J-course" do
      q = build_question("single_choice", 1, [{"A", true}, {"B", false}])
      result = Scoring.compute_total([{q, [1]}], j_config())
      assert result.outcome == :not_applicable
    end
  end
end
