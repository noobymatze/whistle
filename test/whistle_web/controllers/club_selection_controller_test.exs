defmodule WhistleWeb.ClubSelectionControllerTest do
  alias Whistle.ClubsFixtures
  use WhistleWeb.ConnCase, async: true

  import Whistle.AccountsFixtures

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Registrieren"
      assert response =~ ~p"/users/log_in"
      assert response =~ ~p"/users/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account logs the user in and selects an existing club", %{conn: conn} do
      email = unique_user_email()
      club = ClubsFixtures.club_fixture()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == ~p"/users/settings/clubs/select"

      conn = get(conn, ~p"/users/settings/clubs/select")
      response = html_response(conn, 200)
      assert response =~ club.name

      conn = get(conn, ~p"/users/settings/clubs/select/#{club.id}")
      assert redirected_to(conn) == ~p"/"

      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      # User should be able to access their settings and log out
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log_out"
    end

    @tag :capture_log
    test "creates account logs the user in and tries to select a non-existing club", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == ~p"/users/settings/clubs/select"

      conn = get(conn, ~p"/users/settings/clubs/select/50")
      assert redirected_to(conn) == ~p"/users/settings/clubs/select"

      conn = get(conn, ~p"/users/settings/clubs/select")
      response = html_response(conn, 200)
      assert response =~ "Verein konnte nicht gefunden werden"
    end
  end
end
