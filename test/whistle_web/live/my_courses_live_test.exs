defmodule WhistleWeb.MyCoursesLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures

  alias Whistle.Accounts
  alias Whistle.Courses
  alias Whistle.Registrations

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  defp season_fixture_open do
    season_fixture(%{
      start: ~D[2026-01-01],
      start_registration: ~N[2026-01-01 00:00:00],
      end_registration: ~N[2099-12-31 23:59:59],
      year: 2026
    })
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

  defp topic_fixture(course, name) do
    {:ok, topic} = Courses.create_course_date_topic(%{course_id: course.id, name: name})
    topic
  end

  defp mandatory_date_fixture(course, attrs) do
    {:ok, date} =
      Courses.create_course_date(
        Map.merge(
          %{course_id: course.id, date: ~D[2026-04-13], time: ~T[14:00:00], kind: :mandatory},
          attrs
        )
      )

    date
  end

  defp elective_date_fixture(course, topic, attrs) do
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

  describe "my courses online rescheduling" do
    setup do
      season = season_fixture_open()
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      course = online_course_fixture(season)
      topic = topic_fixture(course, "Zitronentarte")
      mandatory1 = mandatory_date_fixture(course, %{date: ~D[2026-04-13], time: ~T[14:00:00]})
      mandatory2 = mandatory_date_fixture(course, %{date: ~D[2026-04-14], time: ~T[15:00:00]})

      elective1 =
        elective_date_fixture(course, topic, %{date: ~D[2026-04-21], time: ~T[16:00:00]})

      elective2 =
        elective_date_fixture(course, topic, %{date: ~D[2026-04-22], time: ~T[18:00:00]})

      {:ok, registration} =
        Registrations.enroll_one(user, course, nil, [mandatory1.id, elective1.id])

      %{
        user: user,
        registration: registration,
        mandatory1: mandatory1,
        mandatory2: mandatory2,
        elective1: elective1,
        elective2: elective2
      }
    end

    test "user can reschedule only the mandatory date", %{
      conn: conn,
      user: user,
      registration: registration,
      mandatory2: mandatory2,
      elective1: elective1
    } do
      {:ok, lv, _html} = conn |> log_in(user) |> live(~p"/my-courses")

      lv
      |> element("#edit-reschedule-#{registration.id}")
      |> render_click()

      assert has_element?(lv, "#reschedule-panel-#{registration.id}")

      lv
      |> element("#reschedule-mandatory-#{registration.id}-#{mandatory2.id}")
      |> render_click()

      lv
      |> element("#save-reschedule-#{registration.id}")
      |> render_click()

      html = render(lv)
      assert html =~ "14.04.2026"
      assert html =~ "21.04.2026"

      selections = Courses.list_date_selections_for_registration(registration.id)
      selection_ids = MapSet.new(selections, & &1.date.id)

      assert MapSet.member?(selection_ids, mandatory2.id)
      assert MapSet.member?(selection_ids, elective1.id)
    end
  end
end
