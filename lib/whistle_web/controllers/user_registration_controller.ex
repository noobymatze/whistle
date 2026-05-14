defmodule WhistleWeb.UserRegistrationController do
  use WhistleWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias Whistle.Accounts
  alias Whistle.Accounts.User

  def new(conn, params) do
    changeset =
      Accounts.change_user_registration(%User{}, %{
        "email" => Map.get(params, "email", "")
      })

    render_registration_form(conn, changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(
          :info,
          registration_flash_message(
            Accounts.deliver_user_confirmation_instructions(
              user,
              &url(~p"/users/confirm/#{&1}")
            )
          )
        )
        |> redirect(to: ~p"/users/confirm")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_registration_form(conn, changeset)
    end
  end

  defp render_registration_form(conn, %Ecto.Changeset{} = changeset) do
    render(conn, :new, form: to_form(changeset))
  end

  defp registration_flash_message({:ok, _email}) do
    "Benutzer erfolgreich erstellt. Bitte bestätige deine E-Mail innerhalb von 3 Tagen."
  end

  defp registration_flash_message({:error, _reason}) do
    "Benutzer erfolgreich erstellt. Die Bestätigungs-E-Mail konnte aktuell nicht gesendet werden. Du kannst sie später erneut anfordern."
  end
end
