defmodule Whistle.SeasonalLicensesTest do
  use Whistle.DataCase

  alias Whistle.Exams
  alias Whistle.Accounts.License
  alias Whistle.Repo

  import Whistle.ExamsFixtures
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures
  import Ecto.Query

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp season_fixture_for_test(year) do
    season_fixture(%{
      year: year,
      start: ~D[2024-01-01],
      start_registration: ~N[2023-10-01 00:00:00],
      end_registration: ~N[2030-12-31 23:59:59]
    })
  end

  defp setup_distribution(course_type) do
    base = %{
      course_type: course_type,
      question_count: 20,
      low_percentage: 50,
      medium_percentage: 30,
      high_percentage: 20,
      duration_seconds: 1800
    }

    thresholds =
      case course_type do
        "F" -> %{l1_threshold: 18, l2_threshold: 15, l3_threshold: 12}
        "G" -> %{pass_threshold: 14}
        _ -> %{}
      end

    Exams.upsert_distribution(Map.merge(base, thresholds))
  end

  defp exam_for_course_type(course_type, user, season) do
    setup_distribution(course_type)
    course = course_fixture(%{type: course_type, season_id: season.id})
    seed_questions_for_course_type(course_type)
    {:ok, exam} = Exams.create_exam(course, [user.id], user.id)
    {exam, course}
  end

  defp submit_all_correct(exam, participant) do
    exam_details = Exams.get_exam_with_details!(exam.id)

    Enum.each(exam_details.questions, fn question ->
      correct_ids = question.choices |> Enum.filter(& &1.is_correct) |> Enum.map(& &1.id)
      Exams.upsert_answer(participant, question, correct_ids)
    end)
  end

  defp finish_and_score(exam) do
    {:ok, exam} = Exams.update_exam_state(exam, "running")
    {:ok, exam} = Exams.update_exam_state(exam, "finished")
    Exams.score_exam(exam)
    exam
  end

  defp get_participant(exam, user) do
    Exams.get_exam_participant(exam.id, user.id)
  end

  defp get_license(user, season) do
    Repo.get_by(License, user_id: user.id, season_id: season.id)
  end

  # ---------------------------------------------------------------------------
  # License type mapping via full score_exam/1 integration
  # ---------------------------------------------------------------------------

  describe "score_exam/1 license type mapping" do
    test "F-course with all correct answers grants L2 (l1_eligible)" do
      season = season_fixture_for_test(2030)
      user = user_fixture()
      {exam, _} = exam_for_course_type("F", user, season)
      exam_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_details.participants)

      submit_all_correct(exam, participant)
      finish_and_score(exam)

      license = get_license(user, season)
      assert license != nil
      assert license.type == :L2
    end

    test "G-course with all correct answers grants L3" do
      season = season_fixture_for_test(2031)
      user = user_fixture()
      {exam, _} = exam_for_course_type("G", user, season)
      exam_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_details.participants)

      submit_all_correct(exam, participant)
      finish_and_score(exam)

      license = get_license(user, season)
      assert license != nil
      assert license.type == :L3
    end

    test "F-course with no answers does not issue a license" do
      season = season_fixture_for_test(2032)
      user = user_fixture()
      {exam, _} = exam_for_course_type("F", user, season)

      finish_and_score(exam)

      assert get_license(user, season) == nil
    end

    test "J-course scoring does not issue a license" do
      season = season_fixture_for_test(2033)
      user = user_fixture()
      {exam, _} = exam_for_course_type("J", user, season)
      exam_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_details.participants)

      submit_all_correct(exam, participant)
      finish_and_score(exam)

      assert get_license(user, season) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # L1 review eligibility tracking
  # ---------------------------------------------------------------------------

  describe "score_exam/1 L1 review eligibility" do
    test "all-correct F-course participant is marked l1_review_eligible" do
      season = season_fixture_for_test(2034)
      user = user_fixture()
      {exam, _} = exam_for_course_type("F", user, season)
      exam_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_details.participants)

      submit_all_correct(exam, participant)
      finish_and_score(exam)

      refreshed = get_participant(exam, user)
      assert refreshed.exam_outcome == "l1_eligible"
      assert refreshed.l1_review_eligible == true
      assert refreshed.license_decision == "granted"
    end

    test "failed F-course participant is not l1_review_eligible" do
      season = season_fixture_for_test(2035)
      user = user_fixture()
      {exam, _} = exam_for_course_type("F", user, season)

      finish_and_score(exam)

      refreshed = get_participant(exam, user)
      assert refreshed.exam_outcome == "fail"
      assert refreshed.l1_review_eligible == false
      assert refreshed.license_decision == "denied"
    end

    test "G-course l3_pass is not l1_review_eligible" do
      season = season_fixture_for_test(2036)
      user = user_fixture()
      {exam, _} = exam_for_course_type("G", user, season)
      exam_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_details.participants)

      submit_all_correct(exam, participant)
      finish_and_score(exam)

      refreshed = get_participant(exam, user)
      assert refreshed.exam_outcome == "l3_pass"
      assert refreshed.l1_review_eligible == false
    end
  end

  # ---------------------------------------------------------------------------
  # Seasonal uniqueness (one license per user per season)
  # ---------------------------------------------------------------------------

  describe "seasonal license uniqueness" do
    test "re-scoring an exam upserts the existing license rather than creating a duplicate" do
      season = season_fixture_for_test(2037)
      user = user_fixture()
      {exam, _} = exam_for_course_type("F", user, season)
      exam_details = Exams.get_exam_with_details!(exam.id)
      participant = hd(exam_details.participants)

      submit_all_correct(exam, participant)
      finish_and_score(exam)
      Exams.score_exam(Exams.get_exam!(exam.id))

      licenses = Repo.all(from l in License, where: l.user_id == ^user.id and l.season_id == ^season.id)
      assert length(licenses) == 1
    end

    test "different users in the same exam each get their own license" do
      season = season_fixture_for_test(2038)
      user1 = user_fixture()
      user2 = user_fixture()
      setup_distribution("F")
      course = course_fixture(%{type: "F", season_id: season.id})
      seed_questions_for_course_type("F")
      {:ok, exam} = Exams.create_exam(course, [user1.id, user2.id], user1.id)
      exam_details = Exams.get_exam_with_details!(exam.id)

      Enum.each(exam_details.participants, fn p ->
        submit_all_correct(exam, p)
      end)

      finish_and_score(exam)

      assert get_license(user1, season) != nil
      assert get_license(user2, season) != nil
    end

    test "same user in two different seasons gets separate licenses" do
      season1 = season_fixture_for_test(2039)
      season2 = season_fixture_for_test(2040)
      user = user_fixture()

      {exam1, _} = exam_for_course_type("F", user, season1)
      exam1_details = Exams.get_exam_with_details!(exam1.id)
      submit_all_correct(exam1, hd(exam1_details.participants))
      finish_and_score(exam1)

      {exam2, _} = exam_for_course_type("F", user, season2)
      exam2_details = Exams.get_exam_with_details!(exam2.id)
      submit_all_correct(exam2, hd(exam2_details.participants))
      finish_and_score(exam2)

      licenses = Repo.all(from l in License, where: l.user_id == ^user.id)
      assert length(licenses) == 2
      season_ids = Enum.map(licenses, & &1.season_id) |> MapSet.new()
      assert MapSet.member?(season_ids, season1.id)
      assert MapSet.member?(season_ids, season2.id)
    end
  end
end
