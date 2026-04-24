defmodule WhistleWeb.RegistrationController do
  use WhistleWeb, :controller

  alias Whistle.Accounts.Role
  alias Whistle.Courses
  alias Whistle.Registrations
  alias Whistle.Seasons

  plug WhistleWeb.Plugs.RequireRole, club_area: true

  def index(conn, params) do
    current_user = conn.assigns.current_user
    current_season = Seasons.get_current_season()
    all_seasons = Seasons.list_seasons()

    selected_season_id =
      case params["season_id"] do
        nil -> current_season && to_string(current_season.id)
        "" -> nil
        id -> id
      end

    with {:ok, season_id} <- parse_optional_id(selected_season_id) do
      filter_opts = if season_id, do: [season_id: season_id], else: []

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
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"course_id" => course_id, "user_id" => user_id}) do
    current_user = conn.assigns.current_user

    with {:ok, course_id} <- parse_id(course_id),
         {:ok, user_id} <- parse_id(user_id) do
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
    else
      _ -> render_not_found(conn)
    end
  end

  def export(conn, params) do
    current_user = conn.assigns.current_user
    selected_season_id = params["season_id"]

    with {:ok, season_id} <- parse_optional_id(selected_season_id) do
      filter_opts = if season_id, do: [season_id: season_id], else: []

      filter_opts =
        if Role.has_role?(current_user, "CLUB_ADMIN") do
          Keyword.put(filter_opts, :club_id, current_user.club_id)
        else
          filter_opts
        end

      filter_opts = Keyword.put(filter_opts, :include_unenrolled, true)

      registrations = Registrations.list_registrations_view(filter_opts)
      date_selections = Courses.list_all_date_selections()
      csv_content = generate_csv(registrations, date_selections)

      timestamp = Calendar.strftime(DateTime.now!("Europe/Berlin"), "%d%m%Y%H%M")
      filename = "Anmeldungen-#{timestamp}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
      |> send_resp(200, csv_content)
    else
      _ -> render_not_found(conn)
    end
  end

  defp generate_csv(registrations, date_selections) do
    has_selections = date_selections != %{}
    date_header = if has_selections, do: ",Gewählte Termine", else: ""
    header = "Id,E-Mail,Name,Geburtstag,Kurs,Lizenznummer,Abgemeldet am#{date_header}\n"

    rows =
      Enum.map(registrations, fn reg ->
        dates_str =
          if has_selections do
            dates = Map.get(date_selections, reg.registration_id, [])

            dates_formatted =
              dates
              |> Enum.sort_by(& &1.kind)
              |> Enum.map(fn d ->
                "#{Calendar.strftime(d.date, "%d.%m.%Y")} #{Time.to_string(d.time) |> String.slice(0, 5)} Uhr"
              end)
              |> Enum.join(", ")

            [dates_formatted]
          else
            []
          end

        ([
           to_string(reg.user_id),
           reg.user_email || "",
           "#{reg.user_first_name} #{reg.user_last_name}",
           format_date(reg.user_birthday),
           escape_csv_field(reg.course_name),
           to_string(reg.license_number || ""),
           format_datetime(reg.unenrolled_at)
         ] ++ dates_str)
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

  defp parse_optional_id(nil), do: {:ok, nil}
  defp parse_optional_id(""), do: {:ok, nil}
  defp parse_optional_id(id), do: parse_id(id)

  defp escape_csv_field(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end

  defp escape_csv_field(value), do: to_string(value)
end
