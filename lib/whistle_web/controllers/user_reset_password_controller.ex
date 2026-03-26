defmodule WhistleWeb.UserResetPasswordController do
  use WhistleWeb, :controller

  alias Whistle.Accounts

  plug :get_user_by_reset_password_token when action in [:edit, :update]

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"user" => %{"username_or_email" => username_or_email}}) do
    if user = Accounts.get_user_by_username_or_email(username_or_email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    conn
    |> put_flash(
      :info,
      "Falls dein Benutzername oder deine E-Mail in unserem System existiert, erhältst du in Kürze Anweisungen zum Zurücksetzen deines Passworts."
    )
    |> redirect(to: ~p"/")
  end

  def edit(conn, _params) do
    render(conn, :edit, changeset: Accounts.change_user_password(conn.assigns.user))
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def update(conn, %{"user" => user_params}) do
    case Accounts.reset_user_password(conn.assigns.user, user_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Passwort erfolgreich zurückgesetzt.")
        |> redirect(to: ~p"/users/log_in")

      {:error, changeset} ->
        render(conn, :edit, changeset: changeset)
    end
  end

  defp get_user_by_reset_password_token(conn, _opts) do
    %{"token" => token} = conn.params

    if user = Accounts.get_user_by_reset_password_token(token) do
      conn |> assign(:user, user) |> assign(:token, token)
    else
      conn
      |> put_flash(
        :error,
        "Der Link zum Zurücksetzen des Passworts ist ungültig oder abgelaufen."
      )
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end
