defmodule WhistleWeb.Plugs.RequireRole do
  @moduledoc """
  Plug for requiring specific roles or role levels.

  This plug provides role-based authorization for Phoenix controllers and LiveViews.
  It integrates with the existing authentication system and provides flexible
  role checking capabilities.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Whistle.Accounts.Role

  def init(opts), do: opts

  def call(conn, opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        # User not authenticated - redirect to login
        conn
        |> put_flash(:error, "Du musst angemeldet sein, um auf diese Seite zuzugreifen.")
        |> redirect(to: "/users/log_in")
        |> halt()

      authorized?(user, opts) ->
        # User is authorized
        conn

      true ->
        # User is authenticated but not authorized
        conn
        |> put_flash(:error, "Du hast keine Berechtigung, diese Seite zu besuchen.")
        |> redirect(to: "/")
        |> halt()
    end
  end

  # Checks if a user is authorized based on the provided options.
  defp authorized?(user, opts) do
    cond do
      opts[:role] ->
        Role.has_role?(user, opts[:role])

      opts[:role_level] ->
        Role.has_role_level?(user, opts[:role_level])

      opts[:roles] ->
        user.role in opts[:roles]

      opts[:admin] ->
        Role.admin?(user)

      opts[:full_admin] ->
        Role.full_admin?(user)

      true ->
        # No specific requirements, just needs to be authenticated
        true
    end
  end
end
