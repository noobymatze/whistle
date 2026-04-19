defmodule Whistle.ExamsAsyncTest do
  use Whistle.DataCase

  import Ecto.Query

  alias Whistle.Exams
  alias Whistle.Exams.ExamParticipant

  import Whistle.ExamsFixtures
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp async_exam_setup do
    user = user_fixture()
    course = course_fixture(%{type: "F"})
    seed_questions_for_course_type("F", 20)

    {:ok, exam} = Exams.create_exam(course, [user.id], user.id, execution_mode: "asynchronous")
    {:ok, exam} = Exams.update_exam_state(exam, "running")

    participant = Exams.get_exam_participant(exam.id, user.id)

    %{user: user, exam: exam, participant: participant}
  end

  # ---------------------------------------------------------------------------
  # create_exam/4 execution_mode
  # ---------------------------------------------------------------------------

  describe "create_exam/4 with execution_mode" do
    test "defaults to synchronous" do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)

      {:ok, exam} = Exams.create_exam(course, [user.id], user.id)
      assert exam.execution_mode == "synchronous"
    end

    test "accepts asynchronous mode" do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)

      {:ok, exam} = Exams.create_exam(course, [user.id], user.id, execution_mode: "asynchronous")
      assert exam.execution_mode == "asynchronous"
    end
  end

  # ---------------------------------------------------------------------------
  # start_async_participant/1
  # ---------------------------------------------------------------------------

  describe "start_async_participant/1" do
    test "transitions participant to running and sets timing fields" do
      %{participant: participant} = async_exam_setup()

      assert participant.async_started_at == nil
      assert participant.async_deadline_at == nil

      {:ok, started} = Exams.start_async_participant(participant)

      assert started.state == "running"
      assert started.async_started_at != nil
      assert started.async_deadline_at != nil

      # Deadline must be ~30 minutes after started_at
      diff = NaiveDateTime.diff(started.async_deadline_at, started.async_started_at, :second)
      assert diff == 30 * 60
    end

    test "returns error when called again on an already-started participant" do
      %{participant: participant} = async_exam_setup()

      {:ok, started} = Exams.start_async_participant(participant)
      assert {:error, :already_started} = Exams.start_async_participant(started)
    end

    test "persists timing state so a reconnecting participant resumes correctly" do
      %{exam: exam, user: user, participant: participant} = async_exam_setup()

      {:ok, started} = Exams.start_async_participant(participant)

      reloaded = Exams.get_exam_participant(exam.id, user.id)
      assert reloaded.async_started_at == started.async_started_at
      assert reloaded.async_deadline_at == started.async_deadline_at
    end
  end

  # ---------------------------------------------------------------------------
  # async_deadline_passed?/1
  # ---------------------------------------------------------------------------

  describe "async_deadline_passed?/1" do
    test "returns false when deadline_at is nil" do
      participant = %ExamParticipant{async_deadline_at: nil}
      refute Exams.async_deadline_passed?(participant)
    end

    test "returns false when deadline is in the future" do
      future = NaiveDateTime.add(NaiveDateTime.utc_now(), 60, :second)
      participant = %ExamParticipant{async_deadline_at: future}
      refute Exams.async_deadline_passed?(participant)
    end

    test "returns true when deadline has passed" do
      past = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :second)
      participant = %ExamParticipant{async_deadline_at: past}
      assert Exams.async_deadline_passed?(participant)
    end
  end

  # ---------------------------------------------------------------------------
  # upsert_answer/3 deadline enforcement
  # ---------------------------------------------------------------------------

  describe "upsert_answer/3 deadline enforcement" do
    test "rejects answer after async deadline" do
      %{exam: exam, participant: participant} = async_exam_setup()

      {:ok, started} = Exams.start_async_participant(participant)

      # Force deadline into the past
      past_deadline = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :second)

      Whistle.Repo.update_all(
        from(p in ExamParticipant, where: p.id == ^started.id),
        set: [async_deadline_at: past_deadline]
      )

      expired = Exams.get_exam_participant(exam.id, started.user_id)
      exam_with_details = Exams.get_exam_with_details!(exam.id)
      question = hd(exam_with_details.questions)
      choice = hd(question.choices)

      assert {:error, :deadline_passed} =
               Exams.upsert_answer(expired, question, [choice.id])
    end

    test "accepts answer before async deadline" do
      %{participant: participant} = async_exam_setup()

      {:ok, started} = Exams.start_async_participant(participant)

      exam_with_details = Exams.get_exam_with_details!(started.exam_id)
      question = hd(exam_with_details.questions)
      choice = hd(question.choices)

      assert {:ok, _answer} = Exams.upsert_answer(started, question, [choice.id])
    end

    test "accepts answer for synchronous participant regardless of async_deadline_at" do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F", 20)
      {:ok, exam} = Exams.create_exam(course, [user.id], user.id)
      {:ok, _} = Exams.update_exam_state(exam, "running")

      participant = Exams.get_exam_participant(exam.id, user.id)
      exam_with_details = Exams.get_exam_with_details!(exam.id)
      question = hd(exam_with_details.questions)
      choice = hd(question.choices)

      assert {:ok, _answer} = Exams.upsert_answer(participant, question, [choice.id])
    end
  end
end
