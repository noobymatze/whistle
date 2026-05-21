defmodule WhistleWeb.UserConfirmationControllerTest do
  use WhistleWeb.ConnCase, async: true

  import Whistle.AccountsFixtures

  alias Whistle.Accounts.{PendingUser, User}
  alias Whistle.Repo

  describe "GET /users/confirm/:token" do
    test "shows only the confirmation action", %{conn: conn} do
      {_pending_user, token} = pending_user_fixture()

      conn = get(conn, ~p"/users/confirm/#{token}")
      html = html_response(conn, 200)

      assert html =~ "Mein Konto bestätigen"
      refute html =~ "Registrieren"
      refute html =~ "Anmelden"
    end
  end

  describe "POST /users/confirm/:token" do
    test "shows a confirmation success page with a login link", %{conn: conn} do
      {pending_user, token} = pending_user_fixture()

      conn = post(conn, ~p"/users/confirm/#{token}")
      html = html_response(conn, 200)

      assert html =~ ~s(id="confirmation-success")
      assert html =~ "Du hast deine E-Mail-Adresse erfolgreich bestätigt."
      assert html =~ "Zur Anmeldung"
      assert html =~ ~s(href="/users/log_in")

      refute Repo.get(PendingUser, pending_user.id)
      assert Repo.get_by(User, username: pending_user.username)
    end
  end
end
