defmodule WhistleWeb.SeasonController do
  use WhistleWeb, :controller

  alias Whistle.Seasons
  alias Whistle.Seasons.Season

  def index(conn, _params) do
    seasons = Seasons.list_seasons()
    render(conn, :index, seasons: seasons)
  end

  def new(conn, _params) do
    changeset = Seasons.change_season(%Season{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"season" => season_params}) do
    case Seasons.create_season(season_params) do
      {:ok, season} ->
        conn
        |> put_flash(:info, "Saison wurde erfolgreich erstellt.")
        |> redirect(to: ~p"/admin/seasons/#{season}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = season <- Seasons.get_season(id) do
      changeset = Seasons.change_season(season)
      render(conn, :edit, season: season, changeset: changeset)
    else
      _ -> render_not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "season" => season_params}) do
    with {:ok, id} <- parse_id(id),
         %{} = season <- Seasons.get_season(id) do
      case Seasons.update_season(season, season_params) do
        {:ok, season} ->
          conn
          |> put_flash(:info, "Saison wurde erfolgreich aktualisiert.")
          |> redirect(to: ~p"/admin/seasons/#{season}/edit")

        {:error, %Ecto.Changeset{} = changeset} ->
          render(conn, :edit, season: season, changeset: changeset)
      end
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = season <- Seasons.get_season(id) do
      {:ok, _season} = Seasons.delete_season(season)

      conn
      |> put_flash(:info, "Saison wurde erfolgreich gelöscht.")
      |> redirect(to: ~p"/admin/seasons")
    else
      _ -> render_not_found(conn)
    end
  end
end
