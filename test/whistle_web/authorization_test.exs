defmodule WhistleWeb.AuthorizationTest do
  use WhistleWeb.ConnCase, async: true

  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures

  alias Phoenix.Flash
  alias Whistle.Accounts

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  # ---------------------------------------------------------------------------
  # 1. Public registration cannot forge elevated roles
  # ---------------------------------------------------------------------------

  describe "public registration role escalation prevention" do
    test "POST /users/register ignores a crafted role param and creates USER", %{conn: conn} do
      params = %{
        "user" => %{
          "email" => "hacker@example.com",
          "username" => "hacker123",
          "password" => "supersecretpassword",
          "first_name" => "Evil",
          "last_name" => "Hacker",
          "birthday" => "1990-01-01",
          "role" => "SUPER_ADMIN"
        }
      }

      conn = post(conn, ~p"/users/register", params)
      assert redirected_to(conn)

      user = Accounts.get_user_by_email("hacker@example.com")
      assert user != nil
      assert user.role == "USER"
    end

    test "POST /users/register also ignores ADMIN role attempt", %{conn: conn} do
      params = %{
        "user" => %{
          "email" => "fakeadmin@example.com",
          "username" => "fakeadmin1",
          "password" => "supersecretpassword",
          "first_name" => "Fake",
          "last_name" => "Admin",
          "birthday" => "1990-01-01",
          "role" => "ADMIN"
        }
      }

      post(conn, ~p"/users/register", params)

      user = Accounts.get_user_by_email("fakeadmin@example.com")
      assert user != nil
      assert user.role == "USER"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Unauthenticated access is blocked for all admin areas
  # ---------------------------------------------------------------------------

  describe "unauthenticated access" do
    test "GET /admin/courses redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/admin/courses")
      assert redirected_to(conn) =~ "/users/log_in"
      refute Flash.get(conn.assigns.flash, :error)
    end

    test "GET /admin/registrations redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/admin/registrations")
      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "GET /admin/clubs redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/admin/clubs")
      assert redirected_to(conn) =~ "/users/log_in"
    end
  end

  # ---------------------------------------------------------------------------
  # 3. USER role cannot access any admin pages
  # ---------------------------------------------------------------------------

  describe "USER role access denial" do
    setup %{conn: conn} do
      user = user_fixture(%{role: "USER"})
      {:ok, conn: log_in(conn, user)}
    end

    test "cannot access course list", %{conn: conn} do
      conn = get(conn, ~p"/admin/courses")
      assert redirected_to(conn) == "/"
    end

    test "cannot access registrations", %{conn: conn} do
      conn = get(conn, ~p"/admin/registrations")
      assert redirected_to(conn) == "/"
    end

    test "cannot access clubs", %{conn: conn} do
      conn = get(conn, ~p"/admin/clubs")
      assert redirected_to(conn) == "/"
    end

    test "cannot access users", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == "/"
    end

    test "cannot access seasons", %{conn: conn} do
      conn = get(conn, ~p"/admin/seasons")
      assert redirected_to(conn) == "/"
    end

    test "cannot access questions", %{conn: conn} do
      conn = get(conn, ~p"/admin/questions")
      assert redirected_to(conn) == "/"
    end
  end

  # ---------------------------------------------------------------------------
  # 4. INSTRUCTOR can access course area but not club/global areas
  # ---------------------------------------------------------------------------

  describe "INSTRUCTOR role authorization" do
    setup %{conn: conn} do
      instructor = user_fixture(%{role: "INSTRUCTOR"})
      {:ok, conn: log_in(conn, instructor)}
    end

    test "can access course list", %{conn: conn} do
      conn = get(conn, ~p"/admin/courses")
      assert html_response(conn, 200)
    end

    test "can access questions", %{conn: conn} do
      conn = get(conn, ~p"/admin/questions")
      assert html_response(conn, 200)
    end

    test "cannot access registrations (club area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/registrations")
      assert redirected_to(conn) == "/"
    end

    test "cannot access users (club area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == "/"
    end

    test "cannot access clubs (global area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/clubs")
      assert redirected_to(conn) == "/"
    end

    test "cannot access seasons (global area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/seasons")
      assert redirected_to(conn) == "/"
    end

    test "cannot delete a course", %{conn: conn} do
      conn = delete(conn, ~p"/admin/courses/999999")
      assert redirected_to(conn) == "/"
    end
  end

  # ---------------------------------------------------------------------------
  # 5. CLUB_ADMIN can access club area but not course or global areas
  # ---------------------------------------------------------------------------

  describe "CLUB_ADMIN role authorization" do
    setup %{conn: conn} do
      club = club_fixture()
      club_admin = user_fixture(%{role: "CLUB_ADMIN", club_id: club.id})
      {:ok, conn: log_in(conn, club_admin), club: club, club_admin: club_admin}
    end

    test "can access registrations", %{conn: conn} do
      conn = get(conn, ~p"/admin/registrations")
      assert html_response(conn, 200)
    end

    test "can access users", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert html_response(conn, 200)
    end

    test "cannot access course list (course area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/courses")
      assert redirected_to(conn) == "/"
    end

    test "cannot access questions (course area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/questions")
      assert redirected_to(conn) == "/"
    end

    test "cannot access clubs (global area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/clubs")
      assert redirected_to(conn) == "/"
    end

    test "cannot access seasons (global area)", %{conn: conn} do
      conn = get(conn, ~p"/admin/seasons")
      assert redirected_to(conn) == "/"
    end

    test "sign-out (delete registration) is allowed – not a true delete", %{conn: conn} do
      # RegistrationController.delete is a sign-out action, not a destructive
      # delete. CLUB_ADMIN must be able to reach it (404 = action reached,
      # no authorization redirect).
      conn = delete(conn, ~p"/admin/registrations/999999/999999")
      assert redirected_to(conn) == "/admin/registrations"
    end
  end

  # ---------------------------------------------------------------------------
  # 6. CLUB_ADMIN query scoping – only sees own club's registrations/users
  # ---------------------------------------------------------------------------

  describe "CLUB_ADMIN query scoping" do
    setup do
      club_a = club_fixture()
      club_b = club_fixture()

      club_admin = user_fixture(%{role: "CLUB_ADMIN", club_id: club_a.id})

      # User in club_a (should be manageable by club_admin)
      user_in_club_a = user_fixture(%{role: "USER", club_id: club_a.id})
      # User in club_b (should NOT be manageable by club_admin)
      user_in_club_b = user_fixture(%{role: "USER", club_id: club_b.id})

      {:ok,
       club_admin: club_admin, user_in_club_a: user_in_club_a, user_in_club_b: user_in_club_b}
    end

    test "list_manageable_users only returns users from own club", %{
      club_admin: club_admin,
      user_in_club_a: user_in_club_a,
      user_in_club_b: user_in_club_b
    } do
      manageable = Accounts.list_manageable_users(club_admin)
      ids = Enum.map(manageable, & &1.id)

      assert user_in_club_a.id in ids
      refute user_in_club_b.id in ids
    end

    test "can_manage_user? returns false for user in another club", %{
      club_admin: club_admin,
      user_in_club_b: user_in_club_b
    } do
      refute Accounts.can_manage_user?(club_admin, user_in_club_b)
    end

    test "can_manage_user? returns true for user in same club", %{
      club_admin: club_admin,
      user_in_club_a: user_in_club_a
    } do
      assert Accounts.can_manage_user?(club_admin, user_in_club_a)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. ADMIN can access all non-public admin pages but cannot delete
  # ---------------------------------------------------------------------------

  describe "ADMIN role authorization" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "ADMIN"})
      {:ok, conn: log_in(conn, admin)}
    end

    test "can access course list", %{conn: conn} do
      conn = get(conn, ~p"/admin/courses")
      assert html_response(conn, 200)
    end

    test "can access registrations", %{conn: conn} do
      conn = get(conn, ~p"/admin/registrations")
      assert html_response(conn, 200)
    end

    test "can access clubs", %{conn: conn} do
      conn = get(conn, ~p"/admin/clubs")
      assert html_response(conn, 200)
    end

    test "can access seasons", %{conn: conn} do
      conn = get(conn, ~p"/admin/seasons")
      assert html_response(conn, 200)
    end

    test "can access users", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert html_response(conn, 200)
    end

    test "user list shows license number and license level", %{conn: conn} do
      target = user_fixture()

      {:ok, target} =
        Accounts.update_user_role(
          target,
          %{license_number: "FD-12345", license_level: "L2"},
          %{role: "SUPER_ADMIN"}
        )

      conn = get(conn, ~p"/admin/users")
      html = html_response(conn, 200)

      assert html =~ ~s(id="user-row-#{target.id}")
      assert html =~ ~s(id="user-license-number-#{target.id}")
      assert html =~ "FD-12345"
      assert html =~ ~s(id="user-license-level-#{target.id}")
      assert html =~ "L2"
    end

    test "cannot delete a course", %{conn: conn} do
      conn = delete(conn, ~p"/admin/courses/999999")
      assert redirected_to(conn) == "/"
    end

    test "cannot delete a club", %{conn: conn} do
      conn = delete(conn, ~p"/admin/clubs/999999")
      assert redirected_to(conn) == "/"
    end

    test "cannot delete a season", %{conn: conn} do
      conn = delete(conn, ~p"/admin/seasons/999999")
      assert redirected_to(conn) == "/"
    end

    test "cannot delete a question", %{conn: conn} do
      conn = delete(conn, ~p"/admin/questions/999999")
      assert redirected_to(conn) == "/"
    end

    test "cannot delete a user", %{conn: conn} do
      conn = delete(conn, ~p"/admin/users/999999")
      assert redirected_to(conn) == "/"
    end
  end

  # ---------------------------------------------------------------------------
  # 8. SUPER_ADMIN can perform delete actions
  # ---------------------------------------------------------------------------

  describe "SUPER_ADMIN delete permissions" do
    setup %{conn: conn} do
      super_admin = user_fixture(%{role: "SUPER_ADMIN"})
      {:ok, conn: log_in(conn, super_admin)}
    end

    # Delete on non-existent IDs should render 404 (not redirect to /),
    # proving that the delete action was reached.
    test "delete on missing course renders 404 (action reached)", %{conn: conn} do
      conn = delete(conn, ~p"/admin/courses/999999")
      assert html_response(conn, 404)
    end

    test "delete on missing club renders 404 (action reached)", %{conn: conn} do
      conn = delete(conn, ~p"/admin/clubs/999999")
      assert html_response(conn, 404)
    end

    test "delete on missing season renders 404 (action reached)", %{conn: conn} do
      conn = delete(conn, ~p"/admin/seasons/999999")
      assert html_response(conn, 404)
    end

    test "delete on missing question renders 404 (action reached)", %{conn: conn} do
      conn = delete(conn, ~p"/admin/questions/999999")
      assert html_response(conn, 404)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Role module helper functions
  # ---------------------------------------------------------------------------

  describe "Role.can_delete?/1" do
    alias Whistle.Accounts.Role

    test "only SUPER_ADMIN returns true" do
      assert Role.can_delete?(%{role: "SUPER_ADMIN"})
      refute Role.can_delete?(%{role: "ADMIN"})
      refute Role.can_delete?(%{role: "CLUB_ADMIN"})
      refute Role.can_delete?(%{role: "INSTRUCTOR"})
      refute Role.can_delete?(%{role: "USER"})
    end
  end

  describe "Role.can_access_course_area?/1" do
    alias Whistle.Accounts.Role

    test "returns true for SUPER_ADMIN, ADMIN, INSTRUCTOR" do
      assert Role.can_access_course_area?(%{role: "SUPER_ADMIN"})
      assert Role.can_access_course_area?(%{role: "ADMIN"})
      assert Role.can_access_course_area?(%{role: "INSTRUCTOR"})
    end

    test "returns false for CLUB_ADMIN and USER" do
      refute Role.can_access_course_area?(%{role: "CLUB_ADMIN"})
      refute Role.can_access_course_area?(%{role: "USER"})
    end
  end

  describe "Role.can_access_club_area?/1" do
    alias Whistle.Accounts.Role

    test "returns true for SUPER_ADMIN, ADMIN, CLUB_ADMIN" do
      assert Role.can_access_club_area?(%{role: "SUPER_ADMIN"})
      assert Role.can_access_club_area?(%{role: "ADMIN"})
      assert Role.can_access_club_area?(%{role: "CLUB_ADMIN"})
    end

    test "returns false for INSTRUCTOR and USER" do
      refute Role.can_access_club_area?(%{role: "INSTRUCTOR"})
      refute Role.can_access_club_area?(%{role: "USER"})
    end
  end

  describe "Role.can_access_global_area?/1" do
    alias Whistle.Accounts.Role

    test "returns true for SUPER_ADMIN and ADMIN" do
      assert Role.can_access_global_area?(%{role: "SUPER_ADMIN"})
      assert Role.can_access_global_area?(%{role: "ADMIN"})
    end

    test "returns false for CLUB_ADMIN, INSTRUCTOR, and USER" do
      refute Role.can_access_global_area?(%{role: "CLUB_ADMIN"})
      refute Role.can_access_global_area?(%{role: "INSTRUCTOR"})
      refute Role.can_access_global_area?(%{role: "USER"})
    end
  end
end
