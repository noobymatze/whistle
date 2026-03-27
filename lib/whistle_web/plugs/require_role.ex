defmodule WhistleWeb.Plugs.RequireRole do
  @moduledoc """
  Plug to require a specific role for a controller or action.

  ## Options

    * `:admin` - Requires admin role (SUPER_ADMIN, ADMIN, or CLUB_ADMIN)
    * `:full_admin` - Requires full admin role (SUPER_ADMIN or ADMIN)
    * `:role` - Requires a specific role string
    * `:role_level` - Requires at least the given role level

  ## Examples

      plug WhistleWeb.Plugs.RequireRole, admin: true
      plug WhistleWeb.Plugs.RequireRole, role: "SUPER_ADMIN"
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Whistle.Accounts.Role

  def init(opts), do: opts

  def call(conn, opts) do
    user = conn.assigns[:current_user]

    authorized =
      cond do
        is_nil(user) ->
          false

        opts[:admin] ->
          Role.admin?(user)

        opts[:full_admin] ->
          Role.full_admin?(user)

        opts[:course_area] ->
          Role.can_access_course_area?(user)

        opts[:club_area] ->
          Role.can_access_club_area?(user)

        opts[:global_area] ->
          Role.can_access_global_area?(user)

        opts[:role] ->
          Role.has_role?(user, opts[:role])

        opts[:role_level] ->
          Role.has_role_level?(user, opts[:role_level])

        true ->
          true
      end

    if authorized do
      conn
    else
      conn
      |> put_flash(:error, "Du hast keine Berechtigung, auf diese Seite zuzugreifen.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
