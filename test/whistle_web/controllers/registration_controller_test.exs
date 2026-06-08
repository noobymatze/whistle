defmodule WhistleWeb.RegistrationControllerTest do
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

  defp element_count(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.count()
  end

  test "ADMIN can filter registrations by participant club", %{conn: conn} do
    season = season_fixture(%{start: ~D[2026-01-01], year: 2026})
    club_a = club_fixture(%{name: "Alpha Verein", short_name: "ALP"})
    club_b = club_fixture(%{name: "Beta Verein", short_name: "BET"})
    admin = user_fixture(%{role: "ADMIN"})
    user_a = user_fixture(%{club_id: club_a.id, first_name: "Anna", last_name: "Alpha"})
    user_b = user_fixture(%{club_id: club_b.id, first_name: "Bernd", last_name: "Beta"})

    course =
      course_fixture(%{
        season_id: season.id,
        name: "Regelkunde",
        type: "Basis",
        organizer_id: club_a.id
      })

    {:ok, registration_a} = Registrations.enroll_one(user_a, course, admin.id)
    {:ok, registration_b} = Registrations.enroll_one(user_b, course, admin.id)

    conn =
      conn
      |> log_in(admin)
      |> get(~p"/admin/registrations?season_id=#{season.id}&club_id=#{club_a.id}")

    html = html_response(conn, 200)

    assert element_count(html, "#registration-filter-form") == 1
    assert element_count(html, "#club_id option[selected][value='#{club_a.id}']") == 1
    assert element_count(html, "#registration-row-#{registration_a.id}") == 1
    assert element_count(html, "#registration-row-#{registration_b.id}") == 0
    assert html =~ "Verein: Alpha Verein"
  end

  test "CLUB_ADMIN remains scoped to own club and does not see the club filter", %{conn: conn} do
    season = season_fixture(%{start: ~D[2026-01-01], year: 2026})
    club_a = club_fixture(%{name: "Alpha Verein", short_name: "ALP"})
    club_b = club_fixture(%{name: "Beta Verein", short_name: "BET"})
    club_admin = user_fixture(%{role: "CLUB_ADMIN", club_id: club_a.id})
    user_a = user_fixture(%{club_id: club_a.id, first_name: "Anna", last_name: "Alpha"})
    user_b = user_fixture(%{club_id: club_b.id, first_name: "Bernd", last_name: "Beta"})

    course =
      course_fixture(%{
        season_id: season.id,
        name: "Regelkunde",
        type: "Basis",
        organizer_id: club_a.id
      })

    {:ok, registration_a} = Registrations.enroll_one(user_a, course, club_admin.id)
    {:ok, registration_b} = Registrations.enroll_one(user_b, course, club_admin.id)

    conn =
      conn
      |> log_in(club_admin)
      |> get(~p"/admin/registrations?season_id=#{season.id}&club_id=#{club_b.id}")

    html = html_response(conn, 200)

    assert element_count(html, "#club_id") == 0
    assert element_count(html, "#registration-row-#{registration_a.id}") == 1
    assert element_count(html, "#registration-row-#{registration_b.id}") == 0
  end

  test "CSV export includes participant club", %{conn: conn} do
    season = season_fixture(%{start: ~D[2026-01-01], year: 2026})
    club = club_fixture(%{name: "CSV Verein", short_name: "CSV"})
    admin = user_fixture(%{role: "ADMIN"})
    user = user_fixture(%{club_id: club.id, first_name: "Clara", last_name: "Club"})

    course =
      course_fixture(%{
        season_id: season.id,
        name: "CSV Kurs",
        type: "Basis",
        organizer_id: club.id
      })

    {:ok, _registration} = Registrations.enroll_one(user, course, admin.id)

    conn =
      conn
      |> log_in(admin)
      |> get(~p"/admin/registrations/export?season_id=#{season.id}")

    csv = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
    assert csv =~ "Id,E-Mail,Name,Geburtstag,Verein,Kurs,Lizenznummer,Abgemeldet am"
    assert csv =~ "CSV Verein"
  end
end
