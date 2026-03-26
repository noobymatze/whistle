defmodule WhistleWeb.ClubSelectionController do
  use WhistleWeb, :controller

  require Logger
  alias Whistle.Accounts
  alias Whistle.Clubs

  def index(conn, _params) do
    clubs = Clubs.list_clubs()
    render(conn, :index, clubs: clubs)
  end

  def select_club(conn, %{"club_id" => club_id}) do
    user = conn.assigns[:current_user]
    club = Clubs.get_club(club_id)

    if club do
      update_user_club(conn, user, club)
    else
      show_club_selection_again(
        conn,
        "Ups, dieser Verein konnte nicht gefunden werden. Bitte wähle einen anderen Verein."
      )
    end
  end

  defp update_user_club(conn, user, club) do
    user_return_to = get_session(conn, :user_return_to)

    case Accounts.update_club(user, club) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Verein wurde erfolgreich gesetzt, viel Spaß!")
        |> redirect(to: user_return_to || ~p"/")

      {:error, _} ->
        show_club_selection_again(
          conn,
          "Leider konnte dieser Verein nicht gesetzt werden, bitte probiere es erneut."
        )
    end
  end

  defp show_club_selection_again(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users/settings/clubs/select")
  end
end
