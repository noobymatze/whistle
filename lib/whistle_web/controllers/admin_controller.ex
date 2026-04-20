defmodule WhistleWeb.AdminController do
  use WhistleWeb, :controller

  alias Whistle.Accounts
  alias Whistle.Accounts.Role
  alias Whistle.Clubs

  plug WhistleWeb.Plugs.RequireRole, club_area: true
  plug WhistleWeb.Plugs.RequireRole, [role: "SUPER_ADMIN"] when action == :delete

  def index(conn, _params) do
    current_user = conn.assigns.current_user

    users =
      if Role.can_access_global_area?(current_user) do
        Accounts.list_users()
      else
        Accounts.list_manageable_users(current_user)
      end

    render(conn, :index, users: users, current_user: current_user)
  end

  def new(conn, _params) do
    current_user = conn.assigns.current_user
    changeset = Accounts.change_user_registration(%Whistle.Accounts.User{})
    clubs = if Role.can_access_global_area?(current_user), do: clubs_for_select(), else: []
    assignable_roles = WhistleWeb.RoleComponents.assignable_roles(current_user)

    render(conn, :edit,
      user: nil,
      changeset: changeset,
      assignable_roles: assignable_roles,
      clubs: clubs,
      current_user: current_user
    )
  end

  def create(conn, %{"user" => user_params}) do
    current_user = conn.assigns.current_user
    requested_role = user_params["role"]

    # Verify role assignment is permitted before touching the database.
    if requested_role && not Role.can_assign_role?(current_user, requested_role) do
      assignable_roles = WhistleWeb.RoleComponents.assignable_roles(current_user)
      clubs = if Role.can_access_global_area?(current_user), do: clubs_for_select(), else: []

      conn
      |> put_flash(:error, "Du hast keine Berechtigung, diese Rolle zuzuweisen.")
      |> render(:edit,
        user: nil,
        changeset: Accounts.change_user_registration(%Whistle.Accounts.User{}),
        assignable_roles: assignable_roles,
        clubs: clubs,
        current_user: current_user
      )
    else
      case Accounts.create_user_as_admin(user_params, current_user) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Benutzer erfolgreich erstellt.")
          |> redirect(to: ~p"/admin/users")

        {:error, %Ecto.Changeset{} = changeset} ->
          assignable_roles = WhistleWeb.RoleComponents.assignable_roles(current_user)
          clubs = if Role.can_access_global_area?(current_user), do: clubs_for_select(), else: []

          render(conn, :edit,
            user: nil,
            changeset: changeset,
            assignable_roles: assignable_roles,
            clubs: clubs,
            current_user: current_user
          )
      end
    end
  end

  def edit(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = user <- Accounts.get_user(id) do
      if Accounts.can_manage_user?(conn.assigns.current_user, user) do
        current_user = conn.assigns.current_user
        changeset = Accounts.change_user_role(user)
        assignable_roles = WhistleWeb.RoleComponents.assignable_roles(current_user)
        clubs = if Role.can_access_global_area?(current_user), do: clubs_for_select(), else: []

        render(conn, :edit,
          user: user,
          changeset: changeset,
          assignable_roles: assignable_roles,
          clubs: clubs,
          current_user: current_user
        )
      else
        conn
        |> put_flash(:error, "Du hast keine Berechtigung, diesen Benutzer zu bearbeiten.")
        |> redirect(to: ~p"/admin/users")
      end
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = user <- Accounts.get_user(id) do
      current_user = conn.assigns.current_user

      cond do
        user.id == current_user.id ->
          conn
          |> put_flash(:error, "Du kannst dein eigenes Konto nicht löschen.")
          |> redirect(to: ~p"/admin/users/#{user}/edit")

        not Accounts.can_manage_user?(current_user, user) ->
          conn
          |> put_flash(:error, "Du hast keine Berechtigung, diesen Benutzer zu löschen.")
          |> redirect(to: ~p"/admin/users/#{user}/edit")

        true ->
          case Accounts.delete_user(user) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "Benutzer wurde erfolgreich gelöscht.")
              |> redirect(to: ~p"/admin/users")

            {:error, _} ->
              conn
              |> put_flash(:error, "Benutzer konnte nicht gelöscht werden.")
              |> redirect(to: ~p"/admin/users/#{user}/edit")
          end
      end
    else
      _ -> render_not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "user" => user_params}) do
    with {:ok, id} <- parse_id(id),
         %{} = user <- Accounts.get_user(id) do
      if Accounts.can_manage_user?(conn.assigns.current_user, user) do
        case Accounts.update_user_role(user, user_params, conn.assigns.current_user) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Benutzer erfolgreich aktualisiert.")
            |> redirect(to: ~p"/admin/users")

          {:error, :unauthorized} ->
            conn
            |> put_flash(:error, "Du hast keine Berechtigung, diese Rolle zuzuweisen.")
            |> redirect(to: ~p"/admin/users/#{user}/edit")

          {:error, %Ecto.Changeset{} = changeset} ->
            current_user = conn.assigns.current_user
            assignable_roles = WhistleWeb.RoleComponents.assignable_roles(current_user)

            clubs =
              if Role.can_access_global_area?(current_user), do: clubs_for_select(), else: []

            render(conn, :edit,
              user: user,
              changeset: changeset,
              assignable_roles: assignable_roles,
              clubs: clubs,
              current_user: current_user
            )
        end
      else
        conn
        |> put_flash(:error, "Du hast keine Berechtigung, diesen Benutzer zu bearbeiten.")
        |> redirect(to: ~p"/admin/users")
      end
    else
      _ -> render_not_found(conn)
    end
  end

  defp clubs_for_select do
    Clubs.list_clubs() |> Enum.map(&{&1.name, &1.id})
  end
end
