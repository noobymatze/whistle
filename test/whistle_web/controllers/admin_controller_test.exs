defmodule WhistleWeb.AdminControllerTest do
  use WhistleWeb.ConnCase

  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures

  setup %{conn: conn} do
    # Create a club first for consistent club_id
    club = club_fixture()

    # Create users with different roles
    super_admin = user_fixture(%{role: "SUPER_ADMIN"})
    admin = user_fixture(%{role: "ADMIN"})
    club_admin = user_fixture(%{role: "CLUB_ADMIN", club_id: club.id})
    instructor = user_fixture(%{role: "INSTRUCTOR", club_id: club.id})
    regular_user = user_fixture(%{role: "USER", club_id: club.id})

    %{
      conn: conn,
      super_admin: super_admin,
      admin: admin,
      club_admin: club_admin,
      instructor: instructor,
      regular_user: regular_user
    }
  end

  describe "GET /admin/users (index)" do
    test "redirects when user is not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == "/users/log_in"
    end

    test "redirects when user is not an admin", %{conn: conn, regular_user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/admin/users")

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Du hast keine Berechtigung, diese Seite zu besuchen."
    end

    test "allows super admin access", %{conn: conn, super_admin: super_admin} do
      conn =
        conn
        |> log_in_user(super_admin)
        |> get(~p"/admin/users")

      assert html_response(conn, 200) =~ "Benutzer"
    end

    test "allows admin access", %{conn: conn, admin: admin} do
      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/users")

      assert html_response(conn, 200) =~ "Benutzer"
    end

    test "allows club admin access", %{conn: conn, club_admin: club_admin} do
      conn =
        conn
        |> log_in_user(club_admin)
        |> get(~p"/admin/users")

      assert html_response(conn, 200) =~ "Benutzer"
    end

    test "shows user list with role badges", %{conn: conn, admin: admin, regular_user: user} do
      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/users")

      response = html_response(conn, 200)
      assert response =~ "Benutzer"
      assert response =~ user.email
    end
  end

  describe "GET /admin/users/:id/edit (edit)" do
    test "shows edit form for manageable user", %{conn: conn, admin: admin, regular_user: user} do
      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/users/#{user}/edit")

      response = html_response(conn, 200)
      assert response =~ "Benutzerrolle bearbeiten"
      assert response =~ user.email
    end

    test "prevents editing users they cannot manage", %{
      conn: conn,
      club_admin: club_admin,
      admin: admin
    } do
      conn =
        conn
        |> log_in_user(club_admin)
        |> get(~p"/admin/users/#{admin}/edit")

      assert redirected_to(conn) == "/admin/users"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Du hast keine Berechtigung, diesen Benutzer zu bearbeiten."
    end
  end

  describe "PUT /admin/users/:id (update)" do
    test "updates user role when authorized", %{conn: conn, admin: admin, regular_user: user} do
      conn =
        conn
        |> log_in_user(admin)
        |> put(~p"/admin/users/#{user}", user: %{role: "INSTRUCTOR"})

      assert redirected_to(conn) == "/admin/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Benutzer erfolgreich aktualisiert."

      updated_user = Whistle.Accounts.get_user!(user.id)
      assert updated_user.role == "INSTRUCTOR"
    end

    test "prevents unauthorized role assignment", %{conn: conn, admin: admin, regular_user: user} do
      conn =
        conn
        |> log_in_user(admin)
        |> put(~p"/admin/users/#{user}", user: %{role: "SUPER_ADMIN"})

      assert redirected_to(conn) == "/admin/users/#{user.id}/edit"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Du hast keine Berechtigung, diese Rolle zuzuweisen."

      # User role should not have changed
      unchanged_user = Whistle.Accounts.get_user!(user.id)
      assert unchanged_user.role == "USER"
    end

    test "validates role value", %{conn: conn, admin: admin, regular_user: user} do
      conn =
        conn
        |> log_in_user(admin)
        |> put(~p"/admin/users/#{user}", user: %{role: "INVALID_ROLE"})

      response = html_response(conn, 200)
      assert response =~ "Benutzerrolle bearbeiten"
      assert response =~ "must be one of"
    end

    test "prevents updating users they cannot manage", %{
      conn: conn,
      club_admin: club_admin,
      admin: admin
    } do
      conn =
        conn
        |> log_in_user(club_admin)
        |> put(~p"/admin/users/#{admin}", user: %{role: "USER"})

      assert redirected_to(conn) == "/admin/users"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Du hast keine Berechtigung, diesen Benutzer zu bearbeiten."
    end
  end
end
