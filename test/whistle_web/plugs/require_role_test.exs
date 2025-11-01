defmodule WhistleWeb.Plugs.RequireRoleTest do
  use WhistleWeb.ConnCase

  import Whistle.AccountsFixtures

  alias WhistleWeb.Plugs.RequireRole

  setup %{conn: conn} do
    %{
      conn:
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.fetch_session()
        |> Phoenix.Controller.fetch_flash(),
      super_admin: user_fixture(%{role: "SUPER_ADMIN"}),
      admin: user_fixture(%{role: "ADMIN"}),
      club_admin: user_fixture(%{role: "CLUB_ADMIN"}),
      instructor: user_fixture(%{role: "INSTRUCTOR"}),
      user: user_fixture(%{role: "USER"})
    }
  end

  describe "call/2 with unauthenticated user" do
    test "redirects to login", %{conn: conn} do
      conn =
        conn
        |> RequireRole.call(RequireRole.init(role: "ADMIN"))

      assert conn.halted
      assert redirected_to(conn) == "/users/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Du musst angemeldet sein, um auf diese Seite zuzugreifen."
    end
  end

  describe "call/2 with exact role requirement" do
    test "allows user with exact role", %{conn: conn, admin: admin} do
      conn =
        conn
        |> assign(:current_user, admin)
        |> RequireRole.call(RequireRole.init(role: "ADMIN"))

      refute conn.halted
    end

    test "denies user with different role", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> RequireRole.call(RequireRole.init(role: "ADMIN"))

      assert conn.halted
      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Du hast keine Berechtigung, diese Seite zu besuchen."
    end
  end

  describe "call/2 with role level requirement" do
    test "allows user with sufficient role level", %{conn: conn, super_admin: super_admin} do
      conn =
        conn
        |> assign(:current_user, super_admin)
        |> RequireRole.call(RequireRole.init(role_level: "ADMIN"))

      refute conn.halted
    end

    test "allows user with exact role level", %{conn: conn, admin: admin} do
      conn =
        conn
        |> assign(:current_user, admin)
        |> RequireRole.call(RequireRole.init(role_level: "ADMIN"))

      refute conn.halted
    end

    test "denies user with insufficient role level", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> RequireRole.call(RequireRole.init(role_level: "ADMIN"))

      assert conn.halted
      assert redirected_to(conn) == "/"
    end
  end

  describe "call/2 with multiple roles" do
    test "allows user with one of the specified roles", %{conn: conn, admin: admin} do
      conn =
        conn
        |> assign(:current_user, admin)
        |> RequireRole.call(RequireRole.init(roles: ["ADMIN", "CLUB_ADMIN"]))

      refute conn.halted
    end

    test "allows user with another specified role", %{conn: conn, club_admin: club_admin} do
      conn =
        conn
        |> assign(:current_user, club_admin)
        |> RequireRole.call(RequireRole.init(roles: ["ADMIN", "CLUB_ADMIN"]))

      refute conn.halted
    end

    test "denies user without any of the specified roles", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> RequireRole.call(RequireRole.init(roles: ["ADMIN", "CLUB_ADMIN"]))

      assert conn.halted
    end
  end

  describe "call/2 with admin requirement" do
    test "allows super admin", %{conn: conn, super_admin: super_admin} do
      conn =
        conn
        |> assign(:current_user, super_admin)
        |> RequireRole.call(RequireRole.init(admin: true))

      refute conn.halted
    end

    test "allows admin", %{conn: conn, admin: admin} do
      conn =
        conn
        |> assign(:current_user, admin)
        |> RequireRole.call(RequireRole.init(admin: true))

      refute conn.halted
    end

    test "allows club admin", %{conn: conn, club_admin: club_admin} do
      conn =
        conn
        |> assign(:current_user, club_admin)
        |> RequireRole.call(RequireRole.init(admin: true))

      refute conn.halted
    end

    test "denies instructor", %{conn: conn, instructor: instructor} do
      conn =
        conn
        |> assign(:current_user, instructor)
        |> RequireRole.call(RequireRole.init(admin: true))

      assert conn.halted
    end

    test "denies regular user", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> RequireRole.call(RequireRole.init(admin: true))

      assert conn.halted
    end
  end

  describe "call/2 with full admin requirement" do
    test "allows super admin", %{conn: conn, super_admin: super_admin} do
      conn =
        conn
        |> assign(:current_user, super_admin)
        |> RequireRole.call(RequireRole.init(full_admin: true))

      refute conn.halted
    end

    test "allows admin", %{conn: conn, admin: admin} do
      conn =
        conn
        |> assign(:current_user, admin)
        |> RequireRole.call(RequireRole.init(full_admin: true))

      refute conn.halted
    end

    test "denies club admin", %{conn: conn, club_admin: club_admin} do
      conn =
        conn
        |> assign(:current_user, club_admin)
        |> RequireRole.call(RequireRole.init(full_admin: true))

      assert conn.halted
    end
  end

  describe "call/2 with no specific requirements" do
    test "allows any authenticated user", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> RequireRole.call(RequireRole.init([]))

      refute conn.halted
    end
  end
end
