defmodule WhistleWeb.CourseControllerTest do
  use WhistleWeb.ConnCase

  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures

  setup :register_and_log_in_user

  @create_attrs %{
    name: "some name",
    type: "some type",
    date: ~D[2024-02-08],
    max_participants: 42,
    max_per_club: 42,
    max_organizer_participants: 42,
    released_at: ~N[2024-02-08 18:45:00]
  }
  @update_attrs %{
    name: "some updated name",
    type: "some updated type",
    date: ~D[2024-02-09],
    max_participants: 43,
    max_per_club: 43,
    max_organizer_participants: 43,
    released_at: ~N[2024-02-09 18:45:00]
  }
  @invalid_attrs %{
    name: nil,
    type: nil,
    date: nil,
    max_participants: nil,
    max_per_club: nil,
    max_organizer_participants: nil,
    released_at: nil
  }

  describe "index" do
    test "lists all courses", %{conn: conn} do
      conn = get(conn, ~p"/admin/courses")
      assert html_response(conn, 200) =~ "Kurse"
    end
  end

  describe "new course" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/admin/courses/new")
      assert html_response(conn, 200) =~ "Neuer Kurs"
    end
  end

  describe "create course" do
    test "redirects to show when data is valid", %{conn: conn} do
      season = season_fixture()
      conn = post(conn, ~p"/admin/courses", course: Map.put(@create_attrs, :season_id, season.id))

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/admin/courses/#{id}/edit"

      conn = get(conn, ~p"/admin/courses/#{id}/edit")
      assert html_response(conn, 200) =~ "Kurs bearbeiten"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/admin/courses", course: @invalid_attrs)
      assert html_response(conn, 200) =~ "Neuer Kurs"
    end
  end

  describe "edit course" do
    setup [:create_course]

    test "renders form for editing chosen course", %{conn: conn, course: course} do
      conn = get(conn, ~p"/admin/courses/#{course}/edit")
      assert html_response(conn, 200) =~ "Kurs bearbeiten"
    end
  end

  describe "update course" do
    setup [:create_course]

    test "redirects when data is valid", %{conn: conn, course: course} do
      conn = put(conn, ~p"/admin/courses/#{course}", course: @update_attrs)
      assert redirected_to(conn) == ~p"/admin/courses/#{course}/edit"

      conn = get(conn, ~p"/admin/courses/#{course}/edit")
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "renders errors when data is invalid", %{conn: conn, course: course} do
      conn = put(conn, ~p"/admin/courses/#{course}", course: @invalid_attrs)
      assert html_response(conn, 200) =~ "Kurs bearbeiten"
    end
  end

  describe "delete course" do
    setup [:create_course]

    test "deletes chosen course", %{conn: conn, course: course} do
      conn = delete(conn, ~p"/admin/courses/#{course}")
      assert redirected_to(conn) == ~p"/admin/courses"

      assert_error_sent 404, fn ->
        get(conn, ~p"/admin/courses/#{course}/edit")
      end
    end
  end

  defp create_course(_) do
    course = course_fixture()
    %{course: course}
  end
end
