defmodule Whistle.ExamsTest do
  use Whistle.DataCase

  alias Whistle.Exams

  import Whistle.ExamsFixtures
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures

  describe "questions" do
    test "create_question/1 with valid attrs creates a question" do
      assert {:ok, question} =
               Exams.create_question(%{
                 type: "single_choice",
                 difficulty: "low",
                 body_markdown: "Was ist Abseits?",
                 status: "active"
               })

      assert question.type == "single_choice"
      assert question.difficulty == "low"
      assert question.status == "active"
    end

    test "create_question/1 rejects invalid type" do
      assert {:error, changeset} =
               Exams.create_question(%{
                 type: "invalid_type",
                 difficulty: "low",
                 body_markdown: "?",
                 status: "active"
               })

      assert errors_on(changeset)[:type]
    end

    test "create_question/1 rejects invalid difficulty" do
      assert {:error, changeset} =
               Exams.create_question(%{
                 type: "single_choice",
                 difficulty: "extreme",
                 body_markdown: "?",
                 status: "active"
               })

      assert errors_on(changeset)[:difficulty]
    end

    test "list_questions/1 filters by status" do
      _draft = question_fixture(%{status: "draft"})
      active = question_fixture(%{status: "active"})

      results = Exams.list_questions(status: "active")
      assert length(results) == 1
      assert hd(results).id == active.id
    end

    test "list_questions/1 filters by course_type" do
      q_f = question_fixture(%{status: "active"})
      q_j = question_fixture(%{status: "active"})

      Exams.set_question_course_types(q_f, ["F"])
      Exams.set_question_course_types(q_j, ["J"])

      results = Exams.list_questions(course_type: "F")
      ids = Enum.map(results, & &1.id)
      assert q_f.id in ids
      refute q_j.id in ids
    end

    test "update_question/2 updates fields" do
      question = question_fixture(%{status: "draft"})
      assert {:ok, updated} = Exams.update_question(question, %{status: "active"})
      assert updated.status == "active"
    end

    test "delete_question/1 deletes the question" do
      question = question_fixture()
      assert {:ok, _} = Exams.delete_question(question)
      assert_raise Ecto.NoResultsError, fn -> Exams.get_question!(question.id) end
    end
  end

  describe "question_choices" do
    test "create_question_choice/1 creates a choice" do
      question = question_fixture()

      assert {:ok, choice} =
               Exams.create_question_choice(%{
                 question_id: question.id,
                 body_markdown: "Antwort A",
                 position: 1,
                 is_correct: true
               })

      assert choice.question_id == question.id
      assert choice.is_correct == true
    end

    test "list_question_choices/1 returns choices ordered by position" do
      question = question_fixture()

      Exams.create_question_choice(%{
        question_id: question.id,
        body_markdown: "B",
        position: 2,
        is_correct: false
      })

      Exams.create_question_choice(%{
        question_id: question.id,
        body_markdown: "A",
        position: 1,
        is_correct: true
      })

      choices = Exams.list_question_choices(question.id)
      assert length(choices) == 2
      assert hd(choices).position == 1
    end
  end

  describe "set_question_course_types/2" do
    test "assigns course types to a question" do
      question = question_fixture()
      assert {:ok, assignments} = Exams.set_question_course_types(question, ["F", "J"])
      assert length(assignments) == 2
    end

    test "replaces existing assignments" do
      question = question_fixture()
      Exams.set_question_course_types(question, ["F", "J"])
      assert {:ok, assignments} = Exams.set_question_course_types(question, ["G"])
      assert length(assignments) == 1
      assert hd(assignments).course_type == "G"
    end

    test "rejects invalid course types" do
      question = question_fixture()
      assert {:error, _} = Exams.set_question_course_types(question, ["X"])
    end
  end

  describe "course_type_question_distributions" do
    test "get_distribution_for_course_type/1 returns defaults when none configured" do
      dist = Exams.get_distribution_for_course_type("F")
      assert dist.low_percentage == 50
      assert dist.medium_percentage == 30
      assert dist.high_percentage == 20
    end

    test "upsert_distribution/1 creates a distribution" do
      assert {:ok, dist} =
               Exams.upsert_distribution(%{
                 course_type: "F",
                 question_count: 25,
                 low_percentage: 40,
                 medium_percentage: 40,
                 high_percentage: 20,
                 l3_threshold: 18,
                 l2_threshold: 24,
                 l1_threshold: 28,
                 duration_seconds: 2400
               })

      assert dist.question_count == 25
      assert dist.low_percentage == 40
      assert dist.l1_threshold == 28
    end

    test "upsert_distribution/1 updates an existing distribution" do
      Exams.upsert_distribution(%{
        course_type: "J",
        question_count: 20,
        low_percentage: 50,
        medium_percentage: 30,
        high_percentage: 20,
        duration_seconds: 3600
      })

      assert {:ok, updated} =
               Exams.upsert_distribution(%{
                 course_type: "J",
                 question_count: 30,
                 low_percentage: 50,
                 medium_percentage: 30,
                 high_percentage: 20,
                 duration_seconds: 3600
               })

      assert updated.question_count == 30
    end

    test "distribution changeset rejects percentages that don't sum to 100" do
      assert {:error, changeset} =
               Exams.upsert_distribution(%{
                 course_type: "G",
                 question_count: 20,
                 low_percentage: 50,
                 medium_percentage: 50,
                 high_percentage: 20,
                 duration_seconds: 3600
               })

      assert errors_on(changeset)[:low_percentage]
    end
  end

  describe "exam_variants" do
    test "create_exam_variant/1 creates a draft variant without questions" do
      assert {:ok, variant} =
               Exams.create_exam_variant(%{
                 name: "F1",
                 course_type: "F",
                 status: "draft",
                 duration_seconds: 1800
               })

      assert variant.name == "F1"
      assert variant.status == "draft"
    end

    test "enabled variants require assigned questions" do
      variant = exam_variant_fixture(%{name: "F2"})

      assert {:error, :exam_variant_has_no_questions} =
               Exams.update_exam_variant(variant, %{status: "enabled"})
    end

    test "set_exam_variant_questions/2 stores ordered question assignments" do
      variant = exam_variant_fixture(%{name: "F3"})
      first = question_with_choices_fixture("F", "low")
      second = question_with_choices_fixture("F", "medium")

      assert {:ok, variant} =
               Exams.set_exam_variant_questions(variant, [{second.id, 2}, {first.id, 1}])

      assignments = variant.variant_questions
      assert Enum.map(assignments, & &1.question_id) == [first.id, second.id]
    end

    test "list_enabled_exam_variants/1 returns only enabled variants for course type" do
      enabled = enabled_exam_variant_fixture("F", 3)
      _draft = exam_variant_fixture(%{name: "F draft", course_type: "F"})
      _other = enabled_exam_variant_fixture("G", 1)

      results = Exams.list_enabled_exam_variants("F")
      assert Enum.map(results, & &1.id) == [enabled.id]
    end
  end

  describe "calculate_difficulty_counts/2" do
    test "produces counts that sum to question_count" do
      distribution = %{low_percentage: 50, medium_percentage: 30, high_percentage: 20}
      dist = struct(Whistle.Exams.CourseTypeQuestionDistribution, distribution)
      counts = Exams.calculate_difficulty_counts(20, dist)

      assert counts.low + counts.medium + counts.high == 20
    end

    test "applies largest-remainder rounding" do
      distribution = %{low_percentage: 50, medium_percentage: 30, high_percentage: 20}
      dist = struct(Whistle.Exams.CourseTypeQuestionDistribution, distribution)
      counts = Exams.calculate_difficulty_counts(20, dist)

      # 50% of 20 = 10.0, 30% of 20 = 6.0, 20% of 20 = 4.0 — exact
      assert counts.low == 10
      assert counts.medium == 6
      assert counts.high == 4
    end

    test "handles non-even distributions" do
      distribution = %{low_percentage: 33, medium_percentage: 33, high_percentage: 34}
      dist = struct(Whistle.Exams.CourseTypeQuestionDistribution, distribution)
      counts = Exams.calculate_difficulty_counts(10, dist)

      # Must sum exactly to 10
      assert counts.low + counts.medium + counts.high == 10
    end
  end

  describe "create_exam/4" do
    setup do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)

      %{user: user, course: course}
    end

    test "creates exam with snapshot and participants", %{user: user, course: course} do
      assert {:ok, exam} = Exams.create_exam(course, [user.id], user.id)

      assert exam.course_id == course.id
      assert exam.course_type == "F"
      assert exam.state == "waiting_room"
      assert exam.question_count == 20

      exam_with_details = Exams.get_exam_with_details!(exam.id)
      assert length(exam_with_details.questions) == 20
      assert length(exam_with_details.participants) == 1
    end

    test "copies question choices into snapshot", %{user: user, course: course} do
      assert {:ok, exam} = Exams.create_exam(course, [user.id], user.id)

      exam_with_details = Exams.get_exam_with_details!(exam.id)
      # Every exam question should have choices loaded
      assert Enum.all?(exam_with_details.questions, fn eq ->
               length(eq.choices) >= 2
             end)
    end

    test "fails when not enough questions for a difficulty", %{user: user} do
      # Remove all low-difficulty questions' course type assignments to simulate shortage
      # by using a course type with no questions at all
      course_no_q = course_fixture(%{type: "G"})

      assert {:error, {:not_enough_questions, "low", _, 0}} =
               Exams.create_exam(course_no_q, [user.id], user.id)
    end

    test "creates exam with multiple participants", %{course: course} do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      assert {:ok, exam} = Exams.create_exam(course, [user1.id, user2.id, user3.id], user1.id)
      exam_with_details = Exams.get_exam_with_details!(exam.id)
      assert length(exam_with_details.participants) == 3
    end

    test "creates exam from enabled variant in variant order", %{user: user, course: course} do
      variant = enabled_exam_variant_fixture("F", 3)

      assert {:ok, exam} =
               Exams.create_exam(course, [user.id], user.id, exam_variant_id: variant.id)

      exam_with_details = Exams.get_exam_with_details!(exam.id)

      assert exam.exam_variant_id == variant.id
      assert exam.question_count == 3
      assert Enum.map(exam_with_details.questions, & &1.position) == [1, 2, 3]
    end

    test "rejects disabled variants", %{user: user, course: course} do
      variant = enabled_exam_variant_fixture("F", 3)
      assert {:ok, variant} = Exams.update_exam_variant(variant, %{status: "disabled"})

      assert {:error, :exam_variant_not_enabled} =
               Exams.create_exam(course, [user.id], user.id, exam_variant_id: variant.id)
    end
  end

  describe "score_exam/1" do
    setup do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)
      {:ok, exam} = Exams.create_exam(course, [user.id], user.id)

      %{user: user, course: course, exam: exam}
    end

    test "scores all participants and sets passed/failed", %{exam: exam} do
      Exams.score_exam(exam)

      exam_with_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_with_details.participants)

      assert participant.achieved_points != nil
      assert participant.max_points != nil
      assert participant.passed != nil
      assert participant.license_decision in ["granted", "denied"]

      assert participant.exam_outcome in [
               "l3_pass",
               "l2_pass",
               "l1_eligible",
               "fail",
               "not_applicable"
             ]
    end

    test "participant with no answers fails", %{exam: exam} do
      Exams.score_exam(exam)

      exam_with_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_with_details.participants)

      # No answers submitted → score should be 0
      assert participant.achieved_points == 0
      refute participant.passed
      assert participant.license_decision == "denied"
      assert participant.exam_outcome == "fail"
    end
  end

  describe "timeout_exam/1" do
    setup do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)
      {:ok, exam} = Exams.create_exam(course, [user.id], user.id)
      {:ok, exam} = Exams.update_exam_state(exam, "running")

      %{user: user, exam: exam}
    end

    test "marks non-submitted participants as timed_out", %{exam: exam} do
      {:ok, _} = Exams.timeout_exam(exam)

      exam_with_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_with_details.participants)

      assert participant.state == "timed_out"
    end

    test "sets exam state to finished", %{exam: exam} do
      {:ok, finished_exam} = Exams.timeout_exam(exam)
      assert finished_exam.state == "finished"
    end

    test "does not change state of already-submitted participants", %{exam: exam, user: user} do
      exam_with_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_with_details.participants)
      assert participant.user_id == user.id

      Exams.update_participant_state(participant, "submitted")
      {:ok, _} = Exams.timeout_exam(exam)

      refreshed = Exams.get_exam_participant(exam.id, user.id)
      assert refreshed.state == "submitted"
    end
  end

  describe "update_exam_state/2" do
    test "transitions exam to running and sets started_at" do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)
      {:ok, exam} = Exams.create_exam(course, [user.id], user.id)

      assert {:ok, running_exam} = Exams.update_exam_state(exam, "running")
      assert running_exam.state == "running"
      assert running_exam.started_at != nil
    end

    test "transitions exam to finished and sets ended_at" do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)
      {:ok, exam} = Exams.create_exam(course, [user.id], user.id)

      assert {:ok, finished_exam} = Exams.update_exam_state(exam, "finished")
      assert finished_exam.state == "finished"
      assert finished_exam.ended_at != nil
    end
  end
end
