defmodule Whistle.CoursesTest do
  use Whistle.DataCase

  alias Whistle.Courses

  describe "courses" do
    alias Whistle.Courses.Course

    import Whistle.CoursesFixtures
    import Whistle.SeasonsFixtures

    @invalid_attrs %{
      name: nil,
      type: nil,
      date: nil,
      max_participants: nil,
      max_per_club: nil,
      max_organizer_participants: nil,
      released_at: nil
    }

    test "list_courses/0 returns all courses" do
      course = course_fixture()
      assert Courses.list_courses() == [course]
    end

    test "get_course!/1 returns the course with given id" do
      course = course_fixture()
      assert Courses.get_course!(course.id) == course
    end

    test "create_course/1 with valid data creates a course" do
      season = season_fixture()

      valid_attrs = %{
        name: "some name",
        type: "some type",
        date: ~D[2024-02-08],
        max_participants: 42,
        max_per_club: 42,
        max_organizer_participants: 42,
        released_at: ~N[2024-02-08 18:45:00],
        season_id: season.id
      }

      assert {:ok, %Course{} = course} = Courses.create_course(valid_attrs)
      assert course.name == "some name"
      assert course.type == "some type"
      assert course.date == ~D[2024-02-08]
      assert course.max_participants == 42
      assert course.max_per_club == 42
      assert course.max_organizer_participants == 42
      assert course.released_at == ~N[2024-02-08 18:45:00]
    end

    test "create_course/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Courses.create_course(@invalid_attrs)
    end

    test "update_course/2 with valid data updates the course" do
      course = course_fixture()

      update_attrs = %{
        name: "some updated name",
        type: "some updated type",
        date: ~D[2024-02-09],
        max_participants: 43,
        max_per_club: 43,
        max_organizer_participants: 43,
        released_at: ~N[2024-02-09 18:45:00]
      }

      assert {:ok, %Course{} = course} = Courses.update_course(course, update_attrs)
      assert course.name == "some updated name"
      assert course.type == "some updated type"
      assert course.date == ~D[2024-02-09]
      assert course.max_participants == 43
      assert course.max_per_club == 43
      assert course.max_organizer_participants == 43
      assert course.released_at == ~N[2024-02-09 18:45:00]
    end

    test "update_course/2 with invalid data returns error changeset" do
      course = course_fixture()
      assert {:error, %Ecto.Changeset{}} = Courses.update_course(course, @invalid_attrs)
      assert course == Courses.get_course!(course.id)
    end

    test "delete_course/1 deletes the course" do
      course = course_fixture()
      assert {:ok, %Course{}} = Courses.delete_course(course)
      assert_raise Ecto.NoResultsError, fn -> Courses.get_course!(course.id) end
    end

    test "change_course/1 returns a course changeset" do
      course = course_fixture()
      assert %Ecto.Changeset{} = Courses.change_course(course)
    end
  end
end
