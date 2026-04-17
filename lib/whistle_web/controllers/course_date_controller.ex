defmodule WhistleWeb.CourseDateController do
  use WhistleWeb, :controller

  alias Whistle.Courses

  plug WhistleWeb.Plugs.RequireRole, course_area: true

  def create(conn, %{"course_id" => course_id, "course_date" => params}) do
    course = Courses.get_course!(course_id)

    case Courses.create_course_date(params) do
      {:ok, _date} ->
        conn
        |> put_flash(:info, "Termin wurde hinzugefügt.")
        |> redirect(to: ~p"/admin/courses/#{course}/edit")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Termin konnte nicht gespeichert werden.")
        |> redirect(to: ~p"/admin/courses/#{course}/edit")
    end
  end

  def delete(conn, %{"course_id" => course_id, "id" => id}) do
    course = Courses.get_course!(course_id)
    date = Courses.get_course_date!(id)
    affected = Courses.count_selections_for_date(date)

    if affected > 0 do
      conn
      |> put_flash(
        :error,
        "Termin kann nicht gelöscht werden: #{affected} Teilnehmer #{if affected == 1, do: "hat", else: "haben"} diesen Termin gewählt. Bitte zuerst die betroffenen Anmeldungen abmelden."
      )
      |> redirect(to: ~p"/admin/courses/#{course}/edit")
    else
      {:ok, _} = Courses.delete_course_date(date)

      conn
      |> put_flash(:info, "Termin wurde gelöscht.")
      |> redirect(to: ~p"/admin/courses/#{course}/edit")
    end
  end
end
