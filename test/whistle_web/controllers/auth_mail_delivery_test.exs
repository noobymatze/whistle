defmodule WhistleWeb.AuthMailDeliveryTest do
  use WhistleWeb.ConnCase, async: false

  import Whistle.AccountsFixtures

  alias Whistle.Accounts
  alias Phoenix.Flash

  setup do
    original_config = Application.get_env(:whistle, Whistle.Mailer)

    Application.put_env(
      :whistle,
      Whistle.Mailer,
      Keyword.merge(original_config || [], adapter: Whistle.TestSupport.FailingSwooshAdapter)
    )

    on_exit(fn ->
      Application.put_env(:whistle, Whistle.Mailer, original_config)
    end)

    :ok
  end

  test "registration succeeds even when confirmation delivery fails", %{conn: conn} do
    params = %{
      "user" => %{
        "username" => unique_username(),
        "email" => unique_user_email(),
        "password" => valid_user_password(),
        "first_name" => "Test",
        "last_name" => "User",
        "birthday" => "1990-01-01"
      }
    }

    conn = post(conn, ~p"/users/register", params)

    assert redirected_to(conn) == "/"

    assert Flash.get(conn.assigns.flash, :info) =~
             "Benutzer erfolgreich erstellt. Die Bestätigungs-E-Mail konnte aktuell nicht gesendet werden."
  end

  test "reset password shows an error when delivery fails", %{conn: conn} do
    user = user_fixture()

    conn =
      post(conn, ~p"/users/reset_password", %{
        "user" => %{"username_or_email" => user.username}
      })

    assert html_response(conn, 200) =~
             "Die E-Mail zum Zurücksetzen des Passworts konnte aktuell nicht gesendet werden."
  end

  test "requesting a confirmation email shows an error when delivery fails", %{conn: conn} do
    user = user_fixture()

    conn =
      post(conn, ~p"/users/confirm", %{
        "user" => %{"email" => user.email}
      })

    assert html_response(conn, 200) =~
             "Die Bestätigungs-E-Mail konnte aktuell nicht gesendet werden."
  end

  test "updating the email shows an error when delivery fails", %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    conn =
      conn
      |> init_test_session(%{})
      |> put_session(:user_token, token)

    conn =
      put(conn, ~p"/users/settings", %{
        "action" => "update_email",
        "current_password" => valid_user_password(),
        "user" => %{"email" => "new-#{unique_user_email()}"}
      })

    assert html_response(conn, 200) =~
             "Die Bestätigungs-E-Mail für deine neue Adresse konnte aktuell nicht gesendet werden."
  end
end
