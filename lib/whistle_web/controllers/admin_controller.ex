defmodule WhistleWeb.AdminController do
  use WhistleWeb, :controller

  alias Whistle.Accounts

  plug WhistleWeb.Plugs.RequireRole, admin: true

  def index(conn, _params) do
    users = Accounts.list_users()
    render(conn, :index, users: users, current_user: conn.assigns.current_user)
  end

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%Whistle.Accounts.User{})
    assignable_roles = WhistleWeb.RoleComponents.assignable_roles(conn.assigns.current_user)

    render(conn, :edit,
      user: nil,
      changeset: changeset,
      assignable_roles: assignable_roles,
      current_user: conn.assigns.current_user
    )
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        # Update role if specified
        if role = user_params["role"] do
          case Accounts.update_user_role(user, role, conn.assigns.current_user) do
            {:ok, _user} ->
              conn
              |> put_flash(:info, "Benutzer erfolgreich erstellt.")
              |> redirect(to: ~p"/admin/users")

            {:error, :unauthorized} ->
              conn
              |> put_flash(:error, "Du hast keine Berechtigung, diese Rolle zuzuweisen.")
              |> redirect(to: ~p"/admin/users/new")

            {:error, changeset} ->
              assignable_roles =
                WhistleWeb.RoleComponents.assignable_roles(conn.assigns.current_user)

              render(conn, :edit,
                user: nil,
                changeset: changeset,
                assignable_roles: assignable_roles
              )
          end
        else
          conn
          |> put_flash(:info, "Benutzer erfolgreich erstellt.")
          |> redirect(to: ~p"/admin/users")
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        assignable_roles = WhistleWeb.RoleComponents.assignable_roles(conn.assigns.current_user)
        render(conn, :edit, user: nil, changeset: changeset, assignable_roles: assignable_roles)
    end
  end

  def edit(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = user <- Accounts.get_user(id) do
      if Accounts.can_manage_user?(conn.assigns.current_user, user) do
        changeset = Accounts.change_user_role(user)
        assignable_roles = WhistleWeb.RoleComponents.assignable_roles(conn.assigns.current_user)

        render(conn, :edit,
          user: user,
          changeset: changeset,
          assignable_roles: assignable_roles,
          current_user: conn.assigns.current_user
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
            assignable_roles =
              WhistleWeb.RoleComponents.assignable_roles(conn.assigns.current_user)

            render(conn, :edit,
              user: user,
              changeset: changeset,
              assignable_roles: assignable_roles
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
end
