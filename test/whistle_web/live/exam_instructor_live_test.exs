defmodule WhistleWeb.ExamInstructorLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures
  import Whistle.ExamsFixtures

  alias Whistle.Accounts
  alias Whistle.Exams

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  defp instructor_fixture do
    user_fixture(%{role: "INSTRUCTOR"})
  end

  defp exam_setup(opts \\ []) do
    instructor = instructor_fixture()
    participant = user_fixture()
    course = course_fixture(%{type: "G"})
    seed_questions_for_course_type("G")

    {:ok, exam} =
      Exams.create_exam(course, [participant.id], instructor.id, opts)

    exam = Exams.get_exam_with_details!(exam.id)
    %{instructor: instructor, participant: participant, exam: exam}
  end

  # ── Access control ────────────────────────────────────────────────────────────

  describe "access control" do
    test "unauthenticated user is redirected to login", %{conn: conn} do
      %{exam: exam} = exam_setup()
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/exams/#{exam.id}")
      assert path =~ "/users/log_in"
    end

    test "regular user without instructor role is redirected", %{conn: conn} do
      %{exam: exam} = exam_setup()
      regular_user = user_fixture()

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in(regular_user) |> live(~p"/admin/exams/#{exam.id}")
    end

    test "instructor can access the exam instructor view", %{conn: conn} do
      %{instructor: instructor, exam: exam} = exam_setup()

      {:ok, _lv, html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      assert html =~ "Warteraum"
    end
  end

  # ── Initial render ─────────────────────────────────────────────────────────────

  describe "initial render" do
    test "shows start and cancel buttons in waiting_room state", %{conn: conn} do
      %{instructor: instructor, exam: exam} = exam_setup()

      {:ok, _lv, html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      assert html =~ "Starten"
      assert html =~ "Abbrechen"
      refute html =~ "Pausieren"
      refute html =~ "Beenden"
    end

    test "shows participant list", %{conn: conn} do
      %{instructor: instructor, participant: participant, exam: exam} = exam_setup()

      {:ok, _lv, html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      assert html =~ participant.first_name
      assert html =~ participant.last_name
    end
  end

  # ── Start ──────────────────────────────────────────────────────────────────────

  describe "start" do
    test "clicking start transitions exam to running", %{conn: conn} do
      %{instructor: instructor, exam: exam} = exam_setup()

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      render_click(lv, "start")
      html = render(lv)

      assert html =~ "Läuft"
      assert html =~ "Pausieren"
      assert html =~ "Beenden"
      refute html =~ "Starten"
    end

    test "clicking start does not start a timer for async exams", %{conn: conn} do
      %{instructor: instructor, exam: exam} =
        exam_setup(execution_mode: "asynchronous")

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      render_click(lv, "start")

      assert Whistle.Exams.ExamTimer.stop_timer(exam.id) == :ok
    end
  end

  # ── Pause / Resume ─────────────────────────────────────────────────────────────

  describe "pause and resume" do
    test "clicking pause transitions running exam to paused", %{conn: conn} do
      %{instructor: instructor, exam: exam} = exam_setup()
      {:ok, exam} = Exams.update_exam_state(exam, "running")

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      render_click(lv, "pause")
      html = render(lv)

      assert html =~ "Pausiert"
      assert html =~ "Fortsetzen"
      refute html =~ "Pausieren"
    end

    test "clicking resume transitions paused exam back to running", %{conn: conn} do
      %{instructor: instructor, exam: exam} = exam_setup()
      {:ok, exam} = Exams.update_exam_state(exam, "running")
      {:ok, exam} = Exams.update_exam_state(exam, "paused")

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      render_click(lv, "resume")
      html = render(lv)

      assert html =~ "Läuft"
      assert html =~ "Pausieren"
      refute html =~ "Fortsetzen"
    end
  end

  # ── Finish ─────────────────────────────────────────────────────────────────────

  describe "finish" do
    test "clicking finish transitions exam to finished and scores participants", %{conn: conn} do
      %{instructor: instructor, participant: participant, exam: exam} = exam_setup()
      {:ok, exam} = Exams.update_exam_state(exam, "running")

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      render_click(lv, "finish")
      html = render(lv)

      assert html =~ "Beendet"
      refute html =~ "Pausieren"
      refute html =~ "Beenden"
      refute html =~ "Starten"

      scored = Exams.get_exam_participant(exam.id, participant.id)
      assert scored.score != nil
      assert scored.passed != nil
    end
  end

  # ── Cancel ─────────────────────────────────────────────────────────────────────

  describe "cancel" do
    test "clicking cancel transitions exam to canceled", %{conn: conn} do
      %{instructor: instructor, exam: exam} = exam_setup()

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      render_click(lv, "cancel")
      html = render(lv)

      assert html =~ "Abgebrochen"
      refute html =~ "Starten"
      refute html =~ "Beenden"
    end
  end

  # ── Participant list updates ───────────────────────────────────────────────────

  describe "participant list updates" do
    test "connected count increases when participant_connected is received", %{conn: conn} do
      %{instructor: instructor, participant: participant, exam: exam} = exam_setup()

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      assert render(lv) =~ "0 verbunden"

      send(lv.pid, {:participant_connected, participant.id})
      assert render(lv) =~ "1 verbunden"
    end

    test "connected count decreases when participant_disconnected is received", %{conn: conn} do
      %{instructor: instructor, participant: participant, exam: exam} = exam_setup()

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      send(lv.pid, {:participant_connected, participant.id})
      assert render(lv) =~ "1 verbunden"

      send(lv.pid, {:participant_disconnected, participant.id})
      assert render(lv) =~ "0 verbunden"
    end

    test "participant state updates when participant_submitted is received", %{conn: conn} do
      %{instructor: instructor, participant: participant, exam: exam} = exam_setup()
      {:ok, _exam} = Exams.update_exam_state(exam, "running")

      p = Exams.get_exam_participant(exam.id, participant.id)
      Exams.update_participant_state(p, "submitted")

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      send(lv.pid, {:participant_submitted, participant.id})
      html = render(lv)

      assert html =~ "Abgegeben"
    end

    test "participant scores are shown after exam_scored is received", %{conn: conn} do
      %{instructor: instructor, exam: exam} = exam_setup()
      {:ok, exam} = Exams.update_exam_state(exam, "running")
      {:ok, exam} = Exams.update_exam_state(exam, "finished")
      Exams.score_exam(exam)
      scored_exam = Exams.get_exam_with_details!(exam.id)

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      send(lv.pid, {:exam_scored, scored_exam})
      html = render(lv)

      assert html =~ "Pkt."
    end

    test "license result selection updates the participant and user license level", %{conn: conn} do
      %{instructor: instructor, participant: participant, exam: exam} = exam_setup()
      {:ok, exam} = Exams.update_exam_state(exam, "running")
      {:ok, exam} = Exams.update_exam_state(exam, "finished")
      Exams.score_exam(exam)
      participant_record = Exams.get_exam_participant(exam.id, participant.id)

      {:ok, lv, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/exams/#{exam.id}")

      render_change(lv, "set_license_result", %{
        "participant_id" => to_string(participant_record.id),
        "license_result" => "L2"
      })

      assert Accounts.get_user!(participant.id).license_level == "L2"
      assert Exams.get_exam_participant(exam.id, participant.id).exam_outcome == "l2_pass"
      assert has_element?(lv, "#license-result-#{participant_record.id}-L2")
    end
  end
end
