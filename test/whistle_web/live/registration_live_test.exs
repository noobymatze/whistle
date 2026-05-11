defmodule WhistleWeb.RegistrationLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures

  alias Phoenix.Flash
  alias Whistle.Accounts
  alias Whistle.Courses
  alias Whistle.Registrations

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp open_season_fixture do
    season_fixture(%{
      start: ~D[2026-01-01],
      start_registration: ~N[2026-01-01 00:00:00],
      end_registration: ~N[2099-12-31 23:59:59],
      year: 2026
    })
  end

  defp offline_course_fixture(season, attrs) do
    course_fixture(
      Map.merge(
        %{
          season_id: season.id,
          type: "F",
          date: ~D[2026-05-10],
          max_participants: 20,
          max_per_club: 6,
          max_organizer_participants: 5,
          released_at: ~N[2026-01-01 00:00:00]
        },
        attrs
      )
    )
  end

  defp online_course_fixture(season, attrs \\ %{}) do
    course_fixture(
      Map.merge(
        %{
          season_id: season.id,
          type: "F",
          online: true,
          date: nil,
          max_participants: 20,
          max_per_club: 6,
          max_organizer_participants: 0,
          released_at: ~N[2026-01-01 00:00:00]
        },
        attrs
      )
    )
  end

  defp topic_fixture(course, name \\ "Thema A") do
    {:ok, topic} = Courses.create_course_date_topic(%{course_id: course.id, name: name})
    topic
  end

  defp mandatory_date_fixture(course, attrs \\ %{}) do
    {:ok, date} =
      Courses.create_course_date(
        Map.merge(
          %{course_id: course.id, date: ~D[2026-04-13], time: ~T[14:00:00], kind: :mandatory},
          attrs
        )
      )

    date
  end

  defp elective_date_fixture(course, topic, attrs \\ %{}) do
    {:ok, date} =
      Courses.create_course_date(
        Map.merge(
          %{
            course_id: course.id,
            date: ~D[2026-04-21],
            time: ~T[16:00:00],
            kind: :elective,
            course_date_topic_id: topic.id
          },
          attrs
        )
      )

    date
  end

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  # ── Page rendering ─────────────────────────────────────────────────────────────

  describe "registration page" do
    test "renders the page for an authenticated user", %{conn: conn} do
      user = user_fixture()
      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ "Kursanmeldung"
    end

    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, redirect}} = live(conn, ~p"/")
      %{to: path} = redirect

      assert path =~ "/users/log_in"
      refute Flash.get(redirect[:flash] || %{}, :error)
    end

    test "shows 'not open yet' when no season exists", %{conn: conn} do
      user = user_fixture()
      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ "noch nicht freigegeben"
    end

    test "shows 'registration ended' when past end_registration", %{conn: conn} do
      _season =
        season_fixture(%{
          start: ~D[2025-01-01],
          start_registration: ~N[2025-01-01 00:00:00],
          end_registration: ~N[2025-06-30 23:59:59],
          year: 2025
        })

      user = user_fixture()
      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ "beendet"
    end

    test "shows offline courses grouped by date when open", %{conn: conn} do
      season = open_season_fixture()
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      _course = offline_course_fixture(season, %{name: "Backen mit Anna", organizer_id: club.id})

      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ "Backen mit Anna"
    end

    test "shows online courses in a separate section", %{conn: conn} do
      season = open_season_fixture()
      user = user_fixture()
      _course = online_course_fixture(season, %{name: "Online-Backen"})

      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ "Online-Kurse"
      assert html =~ "Online-Backen"
    end

    test "shows Online badge for online courses", %{conn: conn} do
      season = open_season_fixture()
      user = user_fixture()
      _course = online_course_fixture(season, %{name: "Online-Kurs"})

      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ "Online"
    end
  end

  # ── Offline enrollment ─────────────────────────────────────────────────────────

  describe "offline course enrollment" do
    setup do
      season = open_season_fixture()
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      course = offline_course_fixture(season, %{organizer_id: club.id, name: "Backen offline"})
      %{user: user, course: course}
    end

    test "can toggle course selection", %{conn: conn, user: user, course: course} do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      assert render(lv) =~ "ring-2 ring-blue-500"
    end

    test "footer appears with selected count after selection", %{
      conn: conn,
      user: user,
      course: course
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      assert render(lv) =~ "1 Kurs ausgewählt"
    end

    test "submitting enrollment registers the user", %{conn: conn, user: user, course: course} do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      lv |> form("#enroll-form") |> render_submit()

      assert Registrations.list_registrations_view(season_id: course.season_id)
             |> Enum.any?(&(&1.user_id == user.id && &1.course_id == course.id))
    end

    test "enrolled course shows as registered", %{conn: conn, user: user, course: course} do
      Registrations.enroll_one(user, course)
      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ "ring-2 ring-blue-500"
    end
  end

  # ── Online date selection UI ───────────────────────────────────────────────────

  describe "online course date selection UI" do
    setup do
      season = open_season_fixture()
      user = user_fixture()
      course = online_course_fixture(season, %{name: "Online-Kurs"})
      topic = topic_fixture(course, "Zitronentarte")
      mandatory = mandatory_date_fixture(course, %{date: ~D[2026-04-13], time: ~T[14:00:00]})
      elective = elective_date_fixture(course, topic, %{date: ~D[2026-04-21], time: ~T[16:00:00]})
      %{user: user, course: course, topic: topic, mandatory: mandatory, elective: elective}
    end

    test "date pickers are hidden before selecting the card", %{conn: conn, user: user} do
      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      refute html =~ "Pflichttermin"
    end

    test "clicking the card expands mandatory and elective date pickers", %{
      conn: conn,
      user: user,
      course: course
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      html = render(lv)
      assert html =~ "Pflichttermin"
      assert html =~ "Wahlpflichttermin"
      assert html =~ "13.04.2026"
      assert html =~ "21.04.2026"
    end

    test "shows topic name under elective dates", %{
      conn: conn,
      user: user,
      course: course,
      topic: topic
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      assert render(lv) =~ topic.name
    end

    test "shows hint when dates not fully selected", %{conn: conn, user: user, course: course} do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      assert render(lv) =~ "Bitte wähle einen Pflicht"
    end

    test "hint disappears when both dates are selected", %{
      conn: conn,
      user: user,
      course: course,
      mandatory: mandatory,
      elective: elective
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{mandatory.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{elective.id}']")
      |> render_click()

      refute render(lv) =~ "Bitte wähle einen Pflicht"
    end

    test "clicking the card again collapses the date pickers", %{
      conn: conn,
      user: user,
      course: course
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      refute render(lv) =~ "Pflichttermin"
    end
  end

  # ── Online enrollment ──────────────────────────────────────────────────────────

  describe "online course enrollment" do
    setup do
      season = open_season_fixture()
      user = user_fixture()
      course = online_course_fixture(season, %{name: "Online-Kurs"})
      topic = topic_fixture(course)
      mandatory = mandatory_date_fixture(course)
      elective = elective_date_fixture(course, topic)
      %{user: user, course: course, mandatory: mandatory, elective: elective}
    end

    test "footer shows selected count after selecting online course", %{
      conn: conn,
      user: user,
      course: course
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      assert render(lv) =~ "1 Kurs ausgewählt"
    end

    test "submitting creates registration with date selections", %{
      conn: conn,
      user: user,
      course: course,
      mandatory: mandatory,
      elective: elective
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{mandatory.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{elective.id}']")
      |> render_click()

      lv |> form("#enroll-form") |> render_submit()

      assert Registrations.list_registrations_view(season_id: course.season_id)
             |> Enum.any?(&(&1.user_id == user.id && &1.course_id == course.id))
    end

    test "shows success flash after enrollment", %{
      conn: conn,
      user: user,
      course: course,
      mandatory: mandatory,
      elective: elective
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{mandatory.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{elective.id}']")
      |> render_click()

      html = lv |> form("#enroll-form") |> render_submit()
      assert html =~ "Erfolgreich angemeldet"
    end

    test "shows error when submitted without date selection", %{
      conn: conn,
      user: user,
      course: course
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      html = lv |> form("#enroll-form") |> render_submit()
      assert html =~ "Bitte wähle genau einen Pflichttermin"
    end

    test "shows remaining seats for each online date and disables full dates", %{
      conn: conn,
      course: course,
      mandatory: mandatory,
      elective: elective
    } do
      other_user = user_fixture()
      third_user = user_fixture()

      {:ok, _registration} =
        Registrations.enroll_one(other_user, course, nil, [mandatory.id, elective.id])

      full_course = Courses.get_course!(course.id)
      {:ok, course} = Courses.update_course(full_course, %{max_participants: 1})

      {:ok, lv, _html} = conn |> log_in(third_user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      assert has_element?(lv, "#online-date-capacity-#{mandatory.id}", "0 Plätze frei")
      assert has_element?(lv, "#online-date-input-#{mandatory.id}[disabled]")
      assert has_element?(lv, "#online-date-capacity-#{elective.id}", "0 Plätze frei")
      assert has_element?(lv, "#online-date-input-#{elective.id}[disabled]")
    end

    test "names the full date when enrollment loses a capacity race", %{
      conn: conn,
      user: user,
      course: course,
      mandatory: mandatory,
      elective: elective
    } do
      {:ok, course} = Courses.update_course(course, %{max_participants: 1})
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{mandatory.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{elective.id}']")
      |> render_click()

      other_user = user_fixture()

      {:ok, _registration} =
        Registrations.enroll_one(other_user, course, nil, [mandatory.id, elective.id])

      html = lv |> form("#enroll-form") |> render_submit()

      assert html =~ "Der Termin am 13.04.2026 um 14:00 Uhr ist ausgebucht."
    end

    test "course shows as registered after successful enrollment", %{
      conn: conn,
      user: user,
      course: course,
      mandatory: mandatory,
      elective: elective
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{mandatory.id}']")
      |> render_click()

      lv
      |> element("[phx-click='select_online_date'][phx-value-date-id='#{elective.id}']")
      |> render_click()

      lv |> form("#enroll-form") |> render_submit()
      assert render(lv) =~ "Angemeldet"
    end
  end

  # ── 2-course rule ──────────────────────────────────────────────────────────────

  describe "2-course rule" do
    test "online course is disabled when user already has 2 registrations", %{conn: conn} do
      season = open_season_fixture()
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      course1 = offline_course_fixture(season, %{organizer_id: club.id, type: "G"})

      course2 =
        offline_course_fixture(season, %{organizer_id: club.id, type: "J", date: ~D[2026-05-15]})

      Registrations.enroll_one(user, course1)
      Registrations.enroll_one(user, course2)

      online_course = online_course_fixture(season)

      {:ok, _lv, html} = conn |> log_in(user) |> live(~p"/")
      assert html =~ online_course.name
      assert html =~ "opacity-50"
    end
  end

  # ── Multiple topics ────────────────────────────────────────────────────────────

  describe "multiple elective topics" do
    test "shows dates under each topic name", %{conn: conn} do
      season = open_season_fixture()
      user = user_fixture()
      course = online_course_fixture(season, %{name: "Multichoice Kurs"})
      topic_a = topic_fixture(course, "Zitronentarte")
      topic_b = topic_fixture(course, "Weihnachtsbäckerei")
      _mandatory = mandatory_date_fixture(course)
      _elective_a = elective_date_fixture(course, topic_a, %{date: ~D[2026-04-21]})
      _elective_b = elective_date_fixture(course, topic_b, %{date: ~D[2026-12-22]})

      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/")

      lv
      |> element("div[phx-click='toggle_online_course'][phx-value-course-id='#{course.id}']")
      |> render_click()

      html = render(lv)

      assert html =~ "Zitronentarte"
      assert html =~ "Weihnachtsbäckerei"
      assert html =~ "21.04.2026"
      assert html =~ "22.12.2026"
    end
  end
end
