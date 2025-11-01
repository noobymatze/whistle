defmodule WhistleWeb.UserResetPasswordControllerTest do
  use WhistleWeb.ConnCase, async: true

  alias Whistle.Accounts
  alias Whistle.Repo
  import Whistle.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/reset_password" do
    test "renders the reset password page", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password")
      response = html_response(conn, 200)
      assert response =~ "Passwort vergessen?"
    end
  end

  describe "POST /users/reset_password" do
    @tag :capture_log
    test "sends a new reset password token with email", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"username_or_email" => user.email}
        })

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Falls dein Benutzername oder deine E-Mail in unserem System existiert"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "reset_password"
    end

    @tag :capture_log
    test "sends a new reset password token with username", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"username_or_email" => user.username}
        })

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Falls dein Benutzername oder deine E-Mail in unserem System existiert"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "reset_password"
    end

    test "does not send reset password token if username or email is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"username_or_email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Falls dein Benutzername oder deine E-Mail in unserem System existiert"

      assert Repo.all(Accounts.UserToken) == []
    end
  end

  describe "GET /users/reset_password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "renders reset password", %{conn: conn, token: token} do
      conn = get(conn, ~p"/users/reset_password/#{token}")
      assert html_response(conn, 200) =~ "Passwort zurücksetzen"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password/oops")
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Der Link zum Zurücksetzen des Passworts ist ungültig oder abgelaufen"
    end
  end

  describe "PUT /users/reset_password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "resets password once", %{conn: conn, user: user, token: token} do
      conn =
        put(conn, ~p"/users/reset_password/#{token}", %{
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Passwort erfolgreich zurückgesetzt"

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not reset password on invalid data", %{conn: conn, token: token} do
      conn =
        put(conn, ~p"/users/reset_password/#{token}", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert html_response(conn, 200) =~ "Hoppla, etwas ist schief gelaufen"
    end

    test "does not reset password with invalid token", %{conn: conn} do
      conn = put(conn, ~p"/users/reset_password/oops")
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Der Link zum Zurücksetzen des Passworts ist ungültig oder abgelaufen"
    end
  end
end
