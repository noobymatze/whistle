defmodule WhistleWeb.RegistrationController do
  use WhistleWeb, :controller

  alias Whistle.Accounts.Role
  alias Whistle.Registrations
  alias Whistle.Seasons

  def index(conn, params) do
    current_user = conn.assigns.current_user
    current_season = Seasons.get_current_season()
    all_seasons = Seasons.list_seasons()
    selected_season_id = params["season_id"] || (current_season && to_string(current_season.id))

    # Build filter options based on user role
    filter_opts =
      if selected_season_id do
        [season_id: String.to_integer(selected_season_id)]
      else
        []
      end

    filter_opts =
      if Role.has_role?(current_user, "CLUB_ADMIN") do
        Keyword.put(filter_opts, :club_id, current_user.club_id)
      else
        filter_opts
      end

    registrations = Registrations.list_registrations_view(filter_opts)

    render(conn, :index,
      registrations: registrations,
      current_user: current_user,
      current_season: current_season,
      seasons: all_seasons,
      selected_season_id: selected_season_id
    )
  end

  def delete(conn, %{"course_id" => course_id, "user_id" => user_id}) do
    course_id = String.to_integer(course_id)
    user_id = String.to_integer(user_id)
    current_user = conn.assigns.current_user

    case Registrations.sign_out(course_id, user_id, current_user.id) do
      {:ok, _registration} ->
        conn
        |> put_flash(:info, "Der Teilnehmer wurde erfolgreich abgemeldet.")
        |> redirect(to: ~p"/admin/registrations")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Anmeldung nicht gefunden.")
        |> redirect(to: ~p"/admin/registrations")
    end
  end
end
