defmodule WhistleWeb.CourseControllerTest do
  use WhistleWeb.ConnCase, async: false

  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures

  alias Whistle.Accounts
  alias Whistle.Registrations

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  test "course CSV export includes participant club", %{conn: conn} do
    season = season_fixture(%{start: ~D[2026-01-01], year: 2026})
    club = club_fixture(%{name: "Kurs Verein", short_name: "KV"})
    instructor = user_fixture(%{role: "INSTRUCTOR"})
    user = user_fixture(%{club_id: club.id, first_name: "Klara", last_name: "Kurs"})

    course =
      course_fixture(%{
        season_id: season.id,
        name: "Kurs Export",
        type: "Basis",
        organizer_id: club.id
      })

    {:ok, _registration} = Registrations.enroll_one(user, course, instructor.id)

    conn =
      conn
      |> log_in(instructor)
      |> get(~p"/admin/courses/#{course.id}/export")

    csv = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
    assert csv =~ "Id,E-Mail,Name,Geburtstag,Verein,Kurs,Lizenznummer,Abgemeldet am"
    assert csv =~ "Kurs Verein"
  end
end
