defmodule WhistleWeb.AssociationController do
  use WhistleWeb, :controller

  alias Whistle.Associations
  alias Whistle.Associations.Association

  plug WhistleWeb.Plugs.RequireRole, global_area: true
  plug WhistleWeb.Plugs.RequireRole, [role: "SUPER_ADMIN"] when action == :delete

  def index(conn, _params) do
    associations = Associations.list_associations()
    render(conn, :index, associations: associations)
  end

  def new(conn, _params) do
    changeset = Associations.change_association(%Association{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"association" => association_params}) do
    case Associations.create_association(association_params) do
      {:ok, association} ->
        conn
        |> put_flash(:info, "Verband wurde erfolgreich erstellt.")
        |> redirect(to: ~p"/admin/associations/#{association}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = association <- Associations.get_association(id) do
      changeset = Associations.change_association(association)
      render(conn, :edit, association: association, changeset: changeset)
    else
      _ -> render_not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "association" => association_params}) do
    with {:ok, id} <- parse_id(id),
         %{} = association <- Associations.get_association(id) do
      case Associations.update_association(association, association_params) do
        {:ok, association} ->
          conn
          |> put_flash(:info, "Verband wurde erfolgreich aktualisiert.")
          |> redirect(to: ~p"/admin/associations/#{association}/edit")

        {:error, %Ecto.Changeset{} = changeset} ->
          render(conn, :edit, association: association, changeset: changeset)
      end
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = association <- Associations.get_association(id) do
      {:ok, _association} = Associations.delete_association(association)

      conn
      |> put_flash(:info, "Verband wurde erfolgreich gelöscht.")
      |> redirect(to: ~p"/admin/associations")
    else
      _ -> render_not_found(conn)
    end
  end
end
