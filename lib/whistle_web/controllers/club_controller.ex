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
    with {:ok, id} <- parse_id(id),
         %{} = club <- Clubs.get_club(id) do
      associations = get_association_options()
      changeset = Clubs.change_club(club)
      render(conn, :edit, club: club, changeset: changeset, associations: associations)
    else
      _ -> render_not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "club" => club_params}) do
    with {:ok, id} <- parse_id(id),
         %{} = club <- Clubs.get_club(id) do
      case Clubs.update_club(club, club_params) do
        {:ok, club} ->
          conn
          |> put_flash(:info, "Verein wurde erfolgreich aktualisiert.")
          |> redirect(to: ~p"/admin/clubs/#{club}/edit")

        {:error, %Ecto.Changeset{} = changeset} ->
          associations = get_association_options()
          render(conn, :edit, club: club, changeset: changeset, associations: associations)
      end
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = club <- Clubs.get_club(id) do
      case Clubs.delete_club(club) do
        {:ok, _club} ->
          conn
          |> put_flash(:info, "Verein wurde erfolgreich gelöscht.")
          |> redirect(to: ~p"/admin/clubs")

        {:error, _changeset} ->
          conn
          |> put_flash(
            :error,
            "Verein konnte nicht gelöscht werden. Möglicherweise sind noch Benutzer oder Kurse diesem Verein zugeordnet."
          )
          |> redirect(to: ~p"/admin/clubs/#{club}/edit")
      end
    else
      _ -> render_not_found(conn)
    end
  end

  defp get_association_options() do
    Associations.list_associations()
    |> Enum.map(fn association -> {association.name, association.id} end)
  end
end
