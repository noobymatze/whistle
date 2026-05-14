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
        confirmation_delivery =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        conn
        |> put_status(:created)
        |> render(:success,
          email: user.email,
          confirmation_delivery: confirmation_delivery
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render_registration_form(conn, changeset)
    end
  end

  defp render_registration_form(conn, %Ecto.Changeset{} = changeset) do
    render(conn, :new, form: to_form(changeset))
  end
end
