defmodule WhistleWeb.CourseController do
  use WhistleWeb, :controller

  alias Whistle.Courses
  alias Whistle.Seasons

  plug WhistleWeb.Plugs.RequireRole, course_area: true
  plug WhistleWeb.Plugs.RequireRole, [role: "SUPER_ADMIN"] when action == :delete

  def index(conn, params) do
    current_season = Seasons.get_current_season()

    selected_season_id =
      case params["season_id"] do
        nil -> current_season && to_string(current_season.id)
        "" -> nil
        id -> id
      end

    all_seasons = Seasons.list_seasons()

    courses =
      if selected_season_id && selected_season_id != "" do
        Courses.list_courses_view(season_id: String.to_integer(selected_season_id))
      else
        Courses.list_courses_view()
      end

    render(conn, :index,
      courses: courses,
      seasons: all_seasons,
      current_season: current_season,
      selected_season_id: selected_season_id
    )
  end

  def export(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = course <- Courses.get_course(id) do
      registrations =
        Whistle.Registrations.list_registrations_view(include_unenrolled: true)
        |> Enum.filter(fn r -> r.course_id == course.id end)

      date_selections =
        if course.online do
          Courses.list_date_selections_for_course(course)
        else
          %{}
        end

      csv_content = generate_csv(registrations, date_selections)

      timestamp = Calendar.strftime(DateTime.now!("Europe/Berlin"), "%d%m%Y%H%M")
      safe_name = String.replace(course.name, ~r/[^a-zA-Z0-9_\-äöüÄÖÜß ]/, "")
      filename = "#{safe_name}-#{timestamp}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
      |> send_resp(200, csv_content)
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = course <- Courses.get_course(id) do
      {:ok, _course} = Courses.delete_course(course)

      conn
      |> put_flash(:info, "Kurs wurde erfolgreich gelöscht.")
      |> redirect(to: ~p"/admin/courses")
    else
      _ -> render_not_found(conn)
    end
  end

  def release(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = course <- Courses.get_course(id) do
      case Courses.release_course(course) do
        {:ok, _course} ->
          conn
          |> put_flash(:info, "Der Kurs #{course.name} wurde erfolgreich freigegeben.")
          |> redirect(to: ~p"/admin/courses")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Kurs konnte nicht freigegeben werden.")
          |> redirect(to: ~p"/admin/courses")
      end
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

  defp escape_csv_field(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end

  defp escape_csv_field(value), do: to_string(value)
end
