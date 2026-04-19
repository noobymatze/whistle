defmodule WhistleWeb.ExamParticipantLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures
  import Whistle.ExamsFixtures

  alias Whistle.Accounts
  alias Whistle.Exams
  alias Whistle.Repo

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  defp async_exam_setup do
    user = user_fixture()
    course = course_fixture(%{type: "F"})
    seed_questions_for_course_type("F")
    {:ok, exam} = Exams.create_exam(course, [user.id], user.id, execution_mode: "asynchronous")
    {:ok, exam} = Exams.update_exam_state(exam, "running")
    participant = Exams.get_exam_participant(exam.id, user.id)
    %{user: user, exam: exam, participant: participant}
  end

  defp sync_exam_setup do
    user = user_fixture()
    course = course_fixture(%{type: "F"})
    seed_questions_for_course_type("F")
    {:ok, exam} = Exams.create_exam(course, [user.id], user.id)
    participant = Exams.get_exam_participant(exam.id, user.id)
    %{user: user, exam: exam, participant: participant}
  end

  # ── 1. Redirect when not a participant ────────────────────────────────────────

  describe "access control" do
    test "unauthenticated user is redirected to login", %{conn: conn} do
      user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F")
      {:ok, exam} = Exams.create_exam(course, [user.id], user.id)

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/exams/#{exam.id}")
      assert path =~ "/users/log_in"
    end

    test "user not registered for exam is redirected with error", %{conn: conn} do
      owner = user_fixture()
      other_user = user_fixture()
      course = course_fixture(%{type: "F"})
      seed_questions_for_course_type("F")
      {:ok, exam} = Exams.create_exam(course, [owner.id], owner.id)

      {:error, {:live_redirect, %{to: path}}} =
        conn |> log_in(other_user) |> live(~p"/exams/#{exam.id}")

      assert path == "/"
    end
  end

  # ── 2. Synchronous exam: waiting room ─────────────────────────────────────────

  describe "synchronous exam - waiting room" do
    test "participant sees waiting room when exam is in waiting_room state", %{conn: conn} do
      %{user: user, exam: exam} = sync_exam_setup()

      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/exams/#{exam.id}")
      assert html =~ "Prüfung"
      assert html =~ "Der Test startet in wenigen Minuten"
    end
  end

  # ── 3. Synchronous exam: question screen after state change ───────────────────

  describe "synchronous exam - state transitions" do
    test "participant sees question screen after exam transitions to running", %{conn: conn} do
      %{user: user, exam: exam} = sync_exam_setup()

      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/exams/#{exam.id}")

      {:ok, running_exam} = Exams.update_exam_state(exam, "running")
      send(lv.pid, {:exam_state_changed, running_exam})

      html = render(lv)
      assert html =~ "Frage 1 von"
    end
  end

  # ── 4. Async exam: pre-start screen ───────────────────────────────────────────

  describe "async exam - pre-start screen" do
    test "shows pre-start screen with start button when exam is running but participant has not started",
         %{conn: conn} do
      %{user: user, exam: exam} = async_exam_setup()

      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/exams/#{exam.id}")

      assert html =~ ~s(id="async-prestart")
      assert html =~ ~s(id="start-async-btn")
      assert html =~ "Test bereit"
    end
  end

  # ── 5. Async exam: start_async event ──────────────────────────────────────────

  describe "async exam - start_async event" do
    test "clicking start_async transitions to question screen with countdown", %{conn: conn} do
      %{user: user, exam: exam} = async_exam_setup()

      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/exams/#{exam.id}")

      render_click(lv, "start_async")
      html = render(lv)

      assert html =~ "Frage 1 von"
      assert html =~ ~s(id="countdown")
      refute html =~ ~s(id="async-prestart")
    end
  end

  # ── 6. Async exam: cannot restart ─────────────────────────────────────────────

  describe "async exam - cannot restart" do
    test "calling start_async a second time does nothing and questions remain visible", %{
      conn: conn
    } do
      %{user: user, exam: exam} = async_exam_setup()

      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/exams/#{exam.id}")

      render_click(lv, "start_async")
      render_click(lv, "start_async")

      html = render(lv)
      assert html =~ "Frage 1 von"
      refute html =~ ~s(id="async-prestart")
    end
  end

  # ── 7. Async exam: reconnect resumes ──────────────────────────────────────────

  describe "async exam - reconnect resumes" do
    test "if participant already has async_started_at set, questions are shown immediately on mount",
         %{conn: conn} do
      %{user: user, exam: exam, participant: participant} = async_exam_setup()

      # Start the participant directly via context (simulates prior session)
      {:ok, _updated} = Exams.start_async_participant(participant)

      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/exams/#{exam.id}")

      assert html =~ "Frage 1 von"
      assert html =~ ~s(id="countdown")
      refute html =~ ~s(id="async-prestart")
    end
  end

  # ── 8. Async exam: deadline auto-submit ───────────────────────────────────────

  describe "async exam - deadline auto-submit" do
    test "sends :tick and participant is auto-submitted when deadline has passed", %{conn: conn} do
      %{user: user, exam: exam, participant: participant} = async_exam_setup()

      # Start the participant
      {:ok, started_participant} = Exams.start_async_participant(participant)

      # Set deadline to 1 second in the past
      past_deadline =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1, :second)
        |> NaiveDateTime.truncate(:second)

      Repo.update!(
        Ecto.Changeset.change(started_participant, async_deadline_at: past_deadline)
      )

      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/exams/#{exam.id}")

      # Send tick to trigger auto-submit
      send(lv.pid, :tick)
      html = render(lv)

      assert html =~ "Abgegeben"
    end
  end
end
