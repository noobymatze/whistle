defmodule WhistleWeb.MyExamsLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures
  import Whistle.ExamsFixtures

  alias Whistle.Accounts
  alias Whistle.Courses
  alias Whistle.Exams

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  test "shows a question-by-question review after an exam is scored", %{conn: conn} do
    user = user_fixture()
    course = course_fixture(%{type: "F"})
    seed_questions_for_course_type("F")

    {:ok, exam} = Exams.create_exam(course, [user.id], user.id)
    {:ok, exam} = Exams.update_exam_state(exam, "finished")

    exam = Exams.get_exam_with_details!(exam.id)
    participant = Exams.get_exam_participant(exam.id, user.id)
    question = hd(exam.questions)
    wrong_choice = Enum.find(question.choices, &(!&1.is_correct))
    correct_choice = Enum.find(question.choices, & &1.is_correct)

    Exams.upsert_answer(participant, question, [wrong_choice.id])
    Exams.score_exam(exam)
    Courses.release_exam_solutions(course)

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/my-exams")

    assert has_element?(view, "#exam-review-#{exam.id}")
    assert has_element?(view, "#review-question-#{question.id}")
    assert has_element?(view, "#review-selected-#{question.id}", wrong_choice.body_markdown)
    assert has_element?(view, "#review-correct-#{question.id}", correct_choice.body_markdown)
  end

  test "hides question-by-question review until solutions are released", %{conn: conn} do
    user = user_fixture()
    course = course_fixture(%{type: "F"})
    seed_questions_for_course_type("F")

    {:ok, exam} = Exams.create_exam(course, [user.id], user.id)
    {:ok, exam} = Exams.update_exam_state(exam, "finished")
    Exams.score_exam(exam)

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/my-exams")

    assert has_element?(view, "#exam-solutions-locked-#{exam.id}")
    refute has_element?(view, "#exam-review-#{exam.id}")
  end

  test "shows score pending message before an exam is scored", %{conn: conn} do
    user = user_fixture()
    course = course_fixture(%{type: "F"})
    seed_questions_for_course_type("F")

    {:ok, exam} = Exams.create_exam(course, [user.id], user.id)

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/my-exams")

    assert has_element?(
             view,
             "#exam-score-pending-#{exam.id}",
             "Dein Score ist noch nicht freigegeben."
           )
  end
end
