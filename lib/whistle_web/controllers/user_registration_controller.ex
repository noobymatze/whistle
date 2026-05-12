defmodule WhistleWeb.UserRegistrationController do
  use WhistleWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias Whistle.Accounts
  alias Whistle.Accounts.User
  alias WhistleWeb.UserAuth

  def new(conn, params) do
    changeset =
      Accounts.change_user_registration(%User{}, %{
        "email" => Map.get(params, "email", "")
      })

    render_registration_form(conn, changeset, Map.get(params, "invite_code", ""))
  end

  def create(conn, %{"user" => user_params} = params) do
    invite_code = Map.get(params, "invite_code", "")

    case Accounts.register_user_with_invitation(user_params, invite_code) do
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

      {:error, :invalid_invitation, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:forbidden)
        |> render_registration_form(
          changeset,
          invite_code,
          "Ungültige oder abgelaufene Einladung."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render_registration_form(conn, changeset, invite_code)
    end
  end

  defp render_registration_form(conn, %Ecto.Changeset{} = changeset, invite_code) do
    render_registration_form(conn, changeset, invite_code, nil)
  end

  defp render_registration_form(
         conn,
         %Ecto.Changeset{} = changeset,
         invite_code,
         invite_code_error
       ) do
    render(conn, :new,
      form: to_form(changeset),
      invite_code: invite_code,
      invite_code_error: invite_code_error
    )
  end

  defp registration_flash_message({:ok, _email}), do: "Benutzer erfolgreich erstellt."

  defp registration_flash_message({:error, _reason}) do
    "Benutzer erfolgreich erstellt. Die Bestätigungs-E-Mail konnte aktuell nicht gesendet werden. Du kannst sie später erneut anfordern."
  end
end
