defmodule WhistleWeb.UserConfirmationController do
  use WhistleWeb, :controller

  alias Whistle.Accounts

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      case Accounts.deliver_user_confirmation_instructions(
             user,
             &url(~p"/users/confirm/#{&1}")
           ) do
        {:ok, _email} ->
          confirmation_sent(conn)

        {:error, :already_confirmed} ->
          confirmation_sent(conn)

        {:error, _reason} ->
          conn
          |> put_flash(
            :error,
            "Die Bestätigungs-E-Mail konnte aktuell nicht gesendet werden. Bitte versuche es später erneut."
          )
          |> render(:new)
      end
    else
      confirmation_sent(conn)
    end
  end

  def edit(conn, %{"token" => token}) do
    render(conn, :edit, token: token)
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def update(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Benutzer erfolgreich bestätigt.")
        |> redirect(to: ~p"/")

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case conn.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            redirect(conn, to: ~p"/")

          %{} ->
            conn
            |> put_flash(
              :error,
              "Der Bestätigungslink für den Benutzer ist ungültig oder abgelaufen."
            )
            |> redirect(to: ~p"/")
        end
    end
  end

  defp confirmation_sent(conn) do
    conn
    |> put_flash(
      :info,
      "Falls deine E-Mail in unserem System existiert und noch nicht bestätigt wurde, " <>
        "erhältst du in Kürze eine E-Mail mit Anweisungen."
    )
    |> redirect(to: ~p"/")
  end
end
