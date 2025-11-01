defmodule WhistleWeb.ClubController do
  use WhistleWeb, :controller

  alias Whistle.Associations
  alias Whistle.Clubs
  alias Whistle.Clubs.Club

  def index(conn, _params) do
    clubs = Clubs.list_clubs()
    render(conn, :index, clubs: clubs)
  end

  def new(conn, _params) do
    associations = get_association_options()
    changeset = Clubs.change_club(%Club{})
    render(conn, :new, changeset: changeset, associations: associations)
  end

  def create(conn, %{"club" => club_params}) do
    case Clubs.create_club(club_params) do
      {:ok, club} ->
        conn
        |> put_flash(:info, "Verein wurde erfolgreich erstellt.")
        |> redirect(to: ~p"/admin/clubs/#{club}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        associations = get_association_options()
        render(conn, :new, changeset: changeset, associations: associations)
    end
  end

  @spec edit(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def edit(conn, %{"id" => id}) do
    club = Clubs.get_club!(id)
    associations = get_association_options()
    changeset = Clubs.change_club(club)
    render(conn, :edit, club: club, changeset: changeset, associations: associations)
  end

  def update(conn, %{"id" => id, "club" => club_params}) do
    club = Clubs.get_club!(id)

    case Clubs.update_club(club, club_params) do
      {:ok, club} ->
        conn
        |> put_flash(:info, "Verein wurde erfolgreich aktualisiert.")
        |> redirect(to: ~p"/admin/clubs/#{club}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        associations = get_association_options()
        render(conn, :edit, club: club, changeset: changeset, associations: associations)
    end
  end

  def delete(conn, %{"id" => id}) do
    club = Clubs.get_club!(id)
    {:ok, _club} = Clubs.delete_club(club)

    conn
    |> put_flash(:info, "Verein wurde erfolgreich gelöscht.")
    |> redirect(to: ~p"/admin/clubs")
  end

  defp get_association_options() do
    Associations.list_associations()
    |> Enum.map(fn association -> {association.name, association.id} end)
  end
end
