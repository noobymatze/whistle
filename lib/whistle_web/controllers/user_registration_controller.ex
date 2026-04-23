defmodule WhistleWeb.UserRegistrationController do
  use WhistleWeb, :controller

  alias Whistle.Accounts
  alias Whistle.Accounts.User
  alias WhistleWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
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
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  defp registration_flash_message({:ok, _email}), do: "Benutzer erfolgreich erstellt."

  defp registration_flash_message({:error, _reason}) do
    "Benutzer erfolgreich erstellt. Die Bestätigungs-E-Mail konnte aktuell nicht gesendet werden. Du kannst sie später erneut anfordern."
  end
end
