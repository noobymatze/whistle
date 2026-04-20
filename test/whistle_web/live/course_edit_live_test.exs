defmodule WhistleWeb.CourseEditLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures

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
end
