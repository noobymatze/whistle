defmodule WhistleWeb.CourseController do
  use WhistleWeb, :controller

  alias Whistle.Clubs
  alias Whistle.Courses
  alias Whistle.Courses.Course
  alias Whistle.Seasons

  def index(conn, params) do
    current_season = Seasons.get_current_season()
    selected_season_id = params["season_id"] || (current_season && to_string(current_season.id))

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

  def new(conn, _params) do
    current_season = Seasons.get_current_season()
    season_id = if current_season, do: current_season.id, else: nil
    changeset = Courses.change_course(%Course{season_id: season_id})
    types = Course.available_types()
    clubs = get_club_options()
    seasons = get_season_options()
    render(conn, :new, changeset: changeset, types: types, clubs: clubs, seasons: seasons)
  end

  def create(conn, %{"course" => course_params}) do
    case Courses.create_course(course_params) do
      {:ok, course} ->
        conn
        |> put_flash(:info, "Kurs wurde erfolgreich erstellt.")
        |> redirect(to: ~p"/admin/courses/#{course}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        types = Course.available_types()
        clubs = get_club_options()
        seasons = get_season_options()
        render(conn, :new, changeset: changeset, types: types, clubs: clubs, seasons: seasons)
    end
  end

  def edit(conn, %{"id" => id}) do
    course = Courses.get_course!(id)
    changeset = Courses.change_course(course)
    types = Course.available_types()
    clubs = get_club_options()
    seasons = get_season_options()

    # Fetch registrations for this course
    registrations =
      Whistle.Registrations.list_registrations_view(include_unenrolled: true)
      |> Enum.filter(fn r -> r.course_id == String.to_integer(id) end)

    exams = Whistle.Exams.list_exams(course_id: course.id)

    render(conn, :edit,
      course: course,
      changeset: changeset,
      types: types,
      clubs: clubs,
      seasons: seasons,
      registrations: registrations,
      exams: exams
    )
  end

  def update(conn, %{"id" => id, "course" => course_params}) do
    course = Courses.get_course!(id)

    case Courses.update_course(course, course_params) do
      {:ok, course} ->
        conn
        |> put_flash(:info, "Kurs wurde erfolgreich aktualisiert.")
        |> redirect(to: ~p"/admin/courses/#{course}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        types = Course.available_types()
        clubs = get_club_options()
        seasons = get_season_options()

        # Fetch registrations for this course
        registrations =
          Whistle.Registrations.list_registrations_view(include_unenrolled: true)
          |> Enum.filter(fn r -> r.course_id == course.id end)

        exams = Whistle.Exams.list_exams(course_id: course.id)

        render(conn, :edit,
          course: course,
          changeset: changeset,
          types: types,
          clubs: clubs,
          seasons: seasons,
          registrations: registrations,
          exams: exams
        )
    end
  end

  def export(conn, %{"id" => id}) do
    course = Courses.get_course!(id)

    registrations =
      Whistle.Registrations.list_registrations_view(include_unenrolled: true)
      |> Enum.filter(fn r -> r.course_id == String.to_integer(id) end)

    csv_content = generate_csv(registrations)

    timestamp = Calendar.strftime(DateTime.now!("Europe/Berlin"), "%d%m%Y%H%M")
    safe_name = String.replace(course.name, ~r/[^a-zA-Z0-9_\-äöüÄÖÜß ]/, "")
    filename = "#{safe_name}-#{timestamp}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, csv_content)
  end

  def delete(conn, %{"id" => id}) do
    course = Courses.get_course!(id)
    {:ok, _course} = Courses.delete_course(course)

    conn
    |> put_flash(:info, "Kurs wurde erfolgreich gelöscht.")
    |> redirect(to: ~p"/admin/courses")
  end

  def release(conn, %{"id" => id}) do
    course = Courses.get_course!(id)

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
  end

  def sign_out_participant(conn, %{"id" => course_id, "user_id" => user_id}) do
    admin_user = conn.assigns.current_user

    case Whistle.Registrations.sign_out(
           String.to_integer(course_id),
           String.to_integer(user_id),
           admin_user.id
         ) do
      {:ok, _registration} ->
        conn
        |> put_flash(:info, "Der Teilnehmer wurde erfolgreich abgemeldet.")
        |> redirect(to: ~p"/admin/courses/#{course_id}/edit")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Registrierung nicht gefunden.")
        |> redirect(to: ~p"/admin/courses/#{course_id}/edit")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Teilnehmer konnte nicht abgemeldet werden.")
        |> redirect(to: ~p"/admin/courses/#{course_id}/edit")
    end
  end

  defp generate_csv(registrations) do
    header = "Id,E-Mail,Name,Geburtstag,Kurs,Lizenznummer,Abgemeldet am\n"

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

  defp get_club_options() do
    Clubs.list_clubs()
    |> Enum.map(fn club -> {club.name, club.id} end)
  end

  defp get_season_options() do
    Seasons.list_seasons()
    |> Enum.map(fn season -> {"Saison #{season.year}", season.id} end)
  end
end
