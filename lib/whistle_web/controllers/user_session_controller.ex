defmodule WhistleWeb.UserSessionController do
  use WhistleWeb, :controller

  alias Whistle.Accounts
  alias WhistleWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    %{"username" => username, "password" => password} = user_params

    if user = Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, "Willkommen zurück!")
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the username is registered.
      render(conn, :new, error_message: "Invalid username or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Erfolgreich abgemeldet.")
    |> UserAuth.log_out_user()
  end
end
