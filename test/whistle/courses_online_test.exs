defmodule Whistle.CoursesOnlineTest do
  use Whistle.DataCase

  alias Whistle.Courses
  alias Whistle.Courses.CourseDateSelection
  alias Whistle.Registrations
  alias Whistle.Repo

  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures
  import Whistle.SeasonsFixtures
  import Ecto.Query

  defp online_course_attrs(season_id, extra \\ %{}) do
    Map.merge(
      %{
        name: "Online F-Kurs",
        type: "F",
        online: true,
        date: nil,
        season_id: season_id,
        max_participants: 20,
        max_per_club: 6,
        max_organizer_participants: 0
      },
      extra
    )
  end

  # ── online flag + CHECK constraint ───────────────────────────────────────────

  describe "create_course/1 - online flag + CHECK constraint" do
    test "online=true, date=nil → valid" do
      season = season_fixture()
      assert {:ok, course} = Courses.create_course(online_course_attrs(season.id))
      assert course.online == true
      assert is_nil(course.date)
    end

    test "online=false, date gesetzt → valid" do
      season = season_fixture()

      assert {:ok, course} =
               Courses.create_course(%{
                 name: "Präsenzkurs",
                 type: "F",
                 online: false,
                 date: ~D[2026-05-01],
                 season_id: season.id,
                 max_participants: 20,
                 max_per_club: 6,
                 max_organizer_participants: 5
               })

      assert course.online == false
      assert course.date == ~D[2026-05-01]
    end

    test "online=true, date gesetzt → changeset error" do
      season = season_fixture()

      assert {:error, changeset} =
               Courses.create_course(online_course_attrs(season.id, %{date: ~D[2026-05-01]}))

      assert %{date: [_]} = errors_on(changeset)
    end

    test "online=false, date=nil → changeset error (date required)" do
      season = season_fixture()

      assert {:error, changeset} =
               Courses.create_course(%{
                 name: "Kurs",
                 type: "F",
                 online: false,
                 date: nil,
                 season_id: season.id
               })

      assert %{date: [_]} = errors_on(changeset)
    end
  end

  # ── course_dates ──────────────────────────────────────────────────────────────

  describe "course_dates" do
    setup do
      season = season_fixture()
      {:ok, course} = Courses.create_course(online_course_attrs(season.id))
      {:ok, topic} = Courses.create_course_date_topic(%{course_id: course.id, name: "Thema A"})
      %{course: course, topic: topic}
    end

    test "mandatory Termin anlegen", %{course: course} do
      assert {:ok, date} =
               Courses.create_course_date(%{
                 course_id: course.id,
                 date: ~D[2026-04-13],
                 time: ~T[14:00:00],
                 kind: :mandatory
               })

      assert date.kind == :mandatory
      assert is_nil(date.course_date_topic_id)
    end

    test "elective Termin mit topic anlegen", %{course: course, topic: topic} do
      assert {:ok, date} =
               Courses.create_course_date(%{
                 course_id: course.id,
                 date: ~D[2026-04-21],
                 time: ~T[16:00:00],
                 kind: :elective,
                 course_date_topic_id: topic.id
               })

      assert date.kind == :elective
      assert date.course_date_topic_id == topic.id
    end

    test "löschen des Kurses cascaded zu course_dates und course_date_selections", %{
      course: course,
      topic: topic
    } do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})

      {:ok, mandatory} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-04-13],
          time: ~T[14:00:00],
          kind: :mandatory
        })

      {:ok, elective} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-04-21],
          time: ~T[16:00:00],
          kind: :elective,
          course_date_topic_id: topic.id
        })

      {:ok, registration} =
        Registrations.enroll_one(user, course, nil, [mandatory.id, elective.id])

      assert Repo.one(
               from s in CourseDateSelection,
                 where: s.registration_id == ^registration.id,
                 select: count(s.id)
             ) == 2

      # Registrations reference courses with on_delete: :nothing — remove first
      Repo.delete_all(from r in Whistle.Registrations.Registration, where: r.course_id == ^course.id)

      {:ok, _} = Courses.delete_course(course)

      assert Repo.all(from d in Whistle.Courses.CourseDate, where: d.course_id == ^course.id) ==
               []

      assert Repo.all(
               from s in CourseDateSelection,
                 where: s.registration_id == ^registration.id
             ) == []
    end
  end

  # ── course_date_topics ───────────────────────────────────────────────────────

  describe "course_date_topics" do
    setup do
      season = season_fixture()
      {:ok, course} = Courses.create_course(online_course_attrs(season.id))
      {:ok, topic} = Courses.create_course_date_topic(%{course_id: course.id, name: "Original"})

      {:ok, date} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-04-21],
          time: ~T[16:00:00],
          kind: :elective,
          course_date_topic_id: topic.id
        })

      %{course: course, topic: topic, date: date}
    end

    test "topic umbenennen ändert nichts an den zugehörigen course_dates", %{
      topic: topic,
      date: date
    } do
      {:ok, updated_topic} = Courses.update_course_date_topic(topic, %{name: "Umbenannt"})
      assert updated_topic.name == "Umbenannt"

      refreshed_date = Courses.get_course_date!(date.id)
      assert refreshed_date.course_date_topic_id == topic.id
    end

    test "löschen eines topics löscht zugehörige elective course_dates und selections", %{
      course: course,
      topic: topic,
      date: date
    } do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})

      {:ok, mandatory} =
        Courses.create_course_date(%{
          course_id: course.id,
          date: ~D[2026-04-13],
          time: ~T[14:00:00],
          kind: :mandatory
        })

      {:ok, registration} =
        Registrations.enroll_one(user, course, nil, [mandatory.id, date.id])

      {:ok, _} = Courses.delete_course_date_topic(topic)

      assert Repo.all(
               from d in Whistle.Courses.CourseDate,
                 where: d.course_date_topic_id == ^topic.id
             ) == []

      # Only the elective selection (pointing to the deleted date) is gone;
      # the mandatory selection is unaffected.
      surviving =
        Repo.all(from s in CourseDateSelection, where: s.registration_id == ^registration.id)

      assert length(surviving) == 1
      assert hd(surviving).course_date_id == mandatory.id
    end
  end
end
