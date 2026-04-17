defmodule WhistleWeb.CourseDateTopicController do
  use WhistleWeb, :controller

  alias Whistle.Courses

  plug WhistleWeb.Plugs.RequireRole, course_area: true

  def create(conn, %{"course_id" => course_id, "course_date_topic" => params}) do
    course = Courses.get_course!(course_id)

    case Courses.create_course_date_topic(params) do
      {:ok, _topic} ->
        conn
        |> put_flash(:info, "Thema wurde angelegt.")
        |> redirect(to: ~p"/admin/courses/#{course}/edit")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Thema konnte nicht gespeichert werden.")
        |> redirect(to: ~p"/admin/courses/#{course}/edit")
    end
  end

  def delete(conn, %{"course_id" => course_id, "id" => id}) do
    course = Courses.get_course!(course_id)
    topic = Courses.get_course_date_topic!(id)
    affected = Courses.count_selections_for_topic(topic)

    if affected > 0 do
      conn
      |> put_flash(
        :error,
        "Thema kann nicht gelöscht werden: #{affected} Teilnehmer #{if affected == 1, do: "hat", else: "haben"} einen Termin aus diesem Thema gewählt. Bitte zuerst die betroffenen Anmeldungen abmelden."
      )
      |> redirect(to: ~p"/admin/courses/#{course}/edit")
    else
      {:ok, _} = Courses.delete_course_date_topic(topic)

      conn
      |> put_flash(:info, "Thema und zugehörige Termine wurden gelöscht.")
      |> redirect(to: ~p"/admin/courses/#{course}/edit")
    end
  end
end
