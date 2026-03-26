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

  def export(conn, params) do
    current_user = conn.assigns.current_user
    selected_season_id = params["season_id"]

    # Build filter options based on user role (same as index action)
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

    # Include unenrolled registrations in export
    filter_opts = Keyword.put(filter_opts, :include_unenrolled, true)

    registrations = Registrations.list_registrations_view(filter_opts)

    # Generate CSV
    csv_content = generate_csv(registrations)

    # Generate filename with timestamp: Anmeldungen-DDMMYYYYHHMM.csv
    timestamp = Calendar.strftime(DateTime.now!("Europe/Berlin"), "%d%m%Y%H%M")
    filename = "Anmeldungen-#{timestamp}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, csv_content)
  end

  defp generate_csv(registrations) do
    # CSV header with German column names
    header = "Id,E-Mail,Name,Geburtstag,Kurs,Lizenznummer,Abgemeldet am\n"

    # CSV rows
    rows =
      Enum.map(registrations, fn reg ->
        [
          to_string(reg.user_id),
          reg.user_email || "",
          "#{reg.user_first_name} #{reg.user_last_name}",
          format_date(reg.user_birthday),
          escape_csv_field(reg.course_name),
          to_string(reg.license_number || ""),
          format_datetime(reg.unenrolled_at)
        ]
        |> Enum.map(&escape_csv_field/1)
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    header <> rows
  end

  defp format_date(nil), do: ""
  defp format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp format_datetime(nil), do: ""
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%d.%m.%Y %H:%M")

  defp escape_csv_field(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end

  defp escape_csv_field(value), do: to_string(value)
end
