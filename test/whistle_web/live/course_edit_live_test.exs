defmodule WhistleWeb.CourseEditLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures

  alias Whistle.Courses
  alias Whistle.Registrations

  defp log_in(conn, user) do
    token = Whistle.Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  defp instructor_fixture do
    user_fixture(%{role: "INSTRUCTOR"})
  end

  describe "new course form" do
    test "online-kurs checkbox appears after switching type to F", %{conn: conn} do
      user = instructor_fixture()
      {:ok, lv, html} = conn |> log_in(user) |> live(~p"/admin/courses/new")

      refute html =~ "Online-Kurs"

      html =
        lv
        |> form("form", %{"course" => %{"type" => "F"}})
        |> render_change()

      assert html =~ "Online-Kurs"
    end

    test "online-kurs checkbox disappears when switching away from F", %{conn: conn} do
      user = instructor_fixture()
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/admin/courses/new")

      lv |> form("form", %{"course" => %{"type" => "F"}}) |> render_change()

      html =
        lv
        |> form("form", %{"course" => %{"type" => "J"}})
        |> render_change()

      refute html =~ "Online-Kurs"
    end

    test "online-kurs checkbox is rendered directly below the type field", %{conn: conn} do
      user = instructor_fixture()
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/admin/courses/new")

      html =
        lv
        |> form("form", %{"course" => %{"type" => "F"}})
        |> render_change()

      # Online-Kurs must appear before Saison in the rendered output
      online_pos = :binary.match(html, "Online-Kurs") |> elem(0)
      saison_pos = :binary.match(html, "Saison") |> elem(0)
      assert online_pos < saison_pos
    end
  end

  describe "edit course form" do
    setup do
      season = season_fixture(%{year: 2026, start: ~D[2026-01-01]})
      course = course_fixture(%{season_id: season.id, type: "J"})
      %{course: course}
    end

    test "online-kurs checkbox appears after switching type to F", %{conn: conn, course: course} do
      user = instructor_fixture()
      {:ok, lv, html} = conn |> log_in(user) |> live(~p"/admin/courses/#{course}/edit")

      refute html =~ "Online-Kurs"

      html =
        lv
        |> form("form", %{"course" => %{"type" => "F"}})
        |> render_change()

      assert html =~ "Online-Kurs"
    end

    test "online-kurs checkbox disappears when switching away from F", %{
      conn: conn,
      course: course
    } do
      user = instructor_fixture()
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/admin/courses/#{course}/edit")

      lv |> form("form", %{"course" => %{"type" => "F"}}) |> render_change()

      html =
        lv
        |> form("form", %{"course" => %{"type" => "G"}})
        |> render_change()

      refute html =~ "Online-Kurs"
    end

    test "no errors shown on type change", %{conn: conn, course: course} do
      user = instructor_fixture()
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/admin/courses/#{course}/edit")

      html =
        lv
        |> form("form", %{"course" => %{"type" => "F"}})
        |> render_change()

      refute html =~ "es ist ein Fehler aufgetreten"
    end
  end

  describe "exam solution release controls" do
    setup do
      season = season_fixture(%{year: 2026, start: ~D[2026-01-01]})
      course = course_fixture(%{season_id: season.id, type: "F"})
      %{course: course}
    end

    test "instructor can release and hide exam solutions", %{conn: conn, course: course} do
      user = instructor_fixture()

      {:ok, view, _html} =
        conn |> log_in(user) |> live(~p"/admin/courses/#{course}/edit?tab=tests")

      assert has_element?(view, "#exam-solutions-release-panel", "Noch nicht")
      assert has_element?(view, "#release-exam-solutions-button")

      render_click(view, "release_exam_solutions")
      html = render(view)

      assert html =~ "Freigegeben am"
      assert has_element?(view, "#hide-exam-solutions-button")
      assert Courses.get_course!(course.id).exam_solutions_released_at != nil

      render_click(view, "hide_exam_solutions")

      assert has_element?(view, "#release-exam-solutions-button")
      assert Courses.get_course!(course.id).exam_solutions_released_at == nil
    end
  end

  describe "participant cancellation overview" do
    test "marks participants who were signed out less than seven days before the course", %{
      conn: conn
    } do
      instructor = instructor_fixture()
      participant = user_fixture()
      season = season_fixture(%{year: 2026, start: ~D[2026-01-01]})

      course =
        course_fixture(%{
          season_id: season.id,
          type: "F",
          date: Date.add(Whistle.Timezone.today_local(), 3)
        })

      {:ok, _registration} =
        Registrations.create_registration(%{course_id: course.id, user_id: participant.id})

      {:ok, view, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/courses/#{course}/edit?tab=teilnehmer")

      render_click(view, "sign_out_participant", %{"user-id" => to_string(participant.id)})

      assert render(view) =~ "Abmeldung weniger als 7 Tage vor Kurs"
    end

    test "groups online course participants by selected date", %{conn: conn} do
      instructor = instructor_fixture()
      participant = user_fixture(%{first_name: "Tina", last_name: "Termin"})
      season = season_fixture(%{year: 2026, start: ~D[2026-01-01]})

      course =
        course_fixture(%{
          season_id: season.id,
          type: "F",
          online: true,
          date: nil,
          max_participants: 10,
          max_per_club: 10,
          max_organizer_participants: 0
        })

      {:ok, topic} = Courses.create_course_date_topic(%{course_id: course.id, name: "Thema"})

      {:ok, mandatory} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-05-13],
          time: ~T[14:00:00],
          kind: :mandatory
        })

      {:ok, elective} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-05-21],
          time: ~T[16:00:00],
          kind: :elective,
          course_date_topic_id: topic.id
        })

      {:ok, registration} =
        Registrations.enroll_one(participant, course, nil, [mandatory.id, elective.id])

      {:ok, view, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/courses/#{course}/edit?tab=teilnehmer")

      assert has_element?(view, "#online-date-participant-overview")
      assert has_element?(view, "#online-date-participants-#{mandatory.id}")
      assert has_element?(view, "#online-date-participant-#{mandatory.id}-#{registration.id}")
      assert has_element?(view, "#online-date-participant-#{elective.id}-#{registration.id}")
    end

    test "offers mail links for participants of individual online dates", %{conn: conn} do
      instructor = instructor_fixture()
      first_participant = user_fixture(%{email: "first-date@example.com"})
      second_participant = user_fixture(%{email: "second-date@example.com"})
      season = season_fixture(%{year: 2026, start: ~D[2026-01-01]})

      course =
        course_fixture(%{
          season_id: season.id,
          type: "F",
          online: true,
          date: nil,
          max_participants: 10,
          max_per_club: 10,
          max_organizer_participants: 0
        })

      {:ok, topic} = Courses.create_course_date_topic(%{course_id: course.id, name: "Thema"})

      {:ok, first_mandatory} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-05-13],
          time: ~T[14:00:00],
          kind: :mandatory
        })

      {:ok, second_mandatory} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-05-14],
          time: ~T[14:00:00],
          kind: :mandatory
        })

      {:ok, first_elective} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-05-21],
          time: ~T[16:00:00],
          kind: :elective,
          course_date_topic_id: topic.id
        })

      {:ok, second_elective} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-05-22],
          time: ~T[16:00:00],
          kind: :elective,
          course_date_topic_id: topic.id
        })

      {:ok, _first_registration} =
        Registrations.enroll_one(first_participant, course, nil, [
          first_mandatory.id,
          first_elective.id
        ])

      {:ok, _second_registration} =
        Registrations.enroll_one(second_participant, course, nil, [
          second_mandatory.id,
          second_elective.id
        ])

      {:ok, view, _html} =
        conn |> log_in(instructor) |> live(~p"/admin/courses/#{course}/edit?tab=teilnehmer")

      assert has_element?(
               view,
               "#mail-all-participants[href='mailto:?bcc=first-date@example.com;second-date@example.com']"
             )

      assert has_element?(
               view,
               "#mail-online-date-#{first_mandatory.id}[href='mailto:?bcc=first-date@example.com']"
             )

      assert has_element?(
               view,
               "#mail-online-date-#{second_mandatory.id}[href='mailto:?bcc=second-date@example.com']"
             )

      refute has_element?(
               view,
               "#mail-online-date-#{first_mandatory.id}[href*='second-date@example.com']"
             )
    end
  end
end
