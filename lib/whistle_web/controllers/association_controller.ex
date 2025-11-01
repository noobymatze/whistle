defmodule WhistleWeb.AssociationController do
  use WhistleWeb, :controller

  alias Whistle.Associations
  alias Whistle.Associations.Association

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
    association = Associations.get_association!(id)
    changeset = Associations.change_association(association)
    render(conn, :edit, association: association, changeset: changeset)
  end

  def update(conn, %{"id" => id, "association" => association_params}) do
    association = Associations.get_association!(id)

    case Associations.update_association(association, association_params) do
      {:ok, association} ->
        conn
        |> put_flash(:info, "Verband wurde erfolgreich aktualisiert.")
        |> redirect(to: ~p"/admin/associations/#{association}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, association: association, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    association = Associations.get_association!(id)
    {:ok, _association} = Associations.delete_association(association)

    conn
    |> put_flash(:info, "Verband wurde erfolgreich gelöscht.")
    |> redirect(to: ~p"/admin/associations")
  end
end
