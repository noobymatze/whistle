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
    render(conn, :new, changeset: changeset, types: types, clubs: clubs)
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
        render(conn, :new, changeset: changeset, types: types, clubs: clubs)
    end
  end

  def edit(conn, %{"id" => id}) do
    course = Courses.get_course!(id)
    changeset = Courses.change_course(course)
    types = Course.available_types()
    clubs = get_club_options()

    # Fetch registrations for this course
    registrations =
      Whistle.Registrations.list_registrations_view(include_unenrolled: true)
      |> Enum.filter(fn r -> r.course_id == String.to_integer(id) end)

    render(conn, :edit,
      course: course,
      changeset: changeset,
      types: types,
      clubs: clubs,
      registrations: registrations
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

        # Fetch registrations for this course
        registrations =
          Whistle.Registrations.list_registrations_view(include_unenrolled: true)
          |> Enum.filter(fn r -> r.course_id == course.id end)

        render(conn, :edit,
          course: course,
          changeset: changeset,
          types: types,
          clubs: clubs,
          registrations: registrations
        )
    end
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

  defp get_club_options() do
    Clubs.list_clubs()
    |> Enum.map(fn club -> {club.name, club.id} end)
  end
end
