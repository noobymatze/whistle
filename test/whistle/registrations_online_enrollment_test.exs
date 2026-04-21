defmodule Whistle.RegistrationsOnlineEnrollmentTest do
  use Whistle.DataCase

  alias Whistle.Registrations
  alias Whistle.Courses
  alias Whistle.Courses.CourseDateSelection
  alias Whistle.Repo

  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures
  import Ecto.Query

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp online_course_fixture(season, attrs \\ %{}) do
    course_fixture(
      Map.merge(
        %{
          season_id: season.id,
          type: "F",
          online: true,
          date: nil,
          max_participants: 20,
          max_per_club: 6,
          max_organizer_participants: 0
        },
        attrs
      )
    )
  end

  defp mandatory_date_fixture(course, attrs \\ %{}) do
    {:ok, date} =
      Courses.create_course_date(
        Map.merge(
          %{course_id: course.id, date: ~D[2026-04-13], time: ~T[14:00:00], kind: :mandatory},
          attrs
        )
      )

    date
  end

  defp elective_date_fixture(course, topic, attrs \\ %{}) do
    {:ok, date} =
      Courses.create_course_date(
        Map.merge(
          %{
            course_id: course.id,
            date: ~D[2026-04-21],
            time: ~T[16:00:00],
            kind: :elective,
            course_date_topic_id: topic.id
          },
          attrs
        )
      )

    date
  end

  defp topic_fixture(course, name \\ "Thema A") do
    {:ok, topic} = Courses.create_course_date_topic(%{course_id: course.id, name: name})
    topic
  end

  defp selection_count(registration_id) do
    Repo.one(
      from s in CourseDateSelection,
        where: s.registration_id == ^registration_id,
        select: count(s.id)
    )
  end

  # ── Happy Path ───────────────────────────────────────────────────────────────

  describe "enroll_one/4 - online course: happy path" do
    test "successful enrollment with valid mandatory + elective selection" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = online_course_fixture(season)
      topic = topic_fixture(course)
      mandatory = mandatory_date_fixture(course)
      elective = elective_date_fixture(course, topic)

      assert {:ok, registration} =
               Registrations.enroll_one(user, course, nil, [mandatory.id, elective.id])

      assert registration.course_id == course.id

      selections =
        Repo.all(from s in CourseDateSelection, where: s.registration_id == ^registration.id)

      assert length(selections) == 2
      date_ids = Enum.map(selections, & &1.course_date_id) |> MapSet.new()
      assert MapSet.member?(date_ids, mandatory.id)
      assert MapSet.member?(date_ids, elective.id)
    end

    test "selections survive sign_out (soft delete leaves them untouched)" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = online_course_fixture(season)
      topic = topic_fixture(course)
      mandatory = mandatory_date_fixture(course)
      elective = elective_date_fixture(course, topic)

      {:ok, registration} =
        Registrations.enroll_one(user, course, nil, [mandatory.id, elective.id])

      {:ok, _} = Registrations.sign_out(course.id, user.id, admin.id)

      assert selection_count(registration.id) == 2
    end

    test "re-enrollment deletes old selections and creates new ones" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = online_course_fixture(season)
      topic = topic_fixture(course)
      mandatory1 = mandatory_date_fixture(course, %{date: ~D[2026-04-13]})
      mandatory2 = mandatory_date_fixture(course, %{date: ~D[2026-04-14]})
      elective = elective_date_fixture(course, topic)

      {:ok, registration} =
        Registrations.enroll_one(user, course, nil, [mandatory1.id, elective.id])

      old_selection_ids =
        Repo.all(
          from s in CourseDateSelection,
            where: s.registration_id == ^registration.id,
            select: s.id
        )

      {:ok, _} = Registrations.sign_out(course.id, user.id, admin.id)

      {:ok, registration2} =
        Registrations.enroll_one(user, course, nil, [mandatory2.id, elective.id])

      assert registration.id == registration2.id

      new_selection_ids =
        Repo.all(
          from s in CourseDateSelection,
            where: s.registration_id == ^registration2.id,
            select: s.id
        )

      assert length(new_selection_ids) == 2
      assert MapSet.disjoint?(MapSet.new(old_selection_ids), MapSet.new(new_selection_ids))
    end
  end

  describe "reschedule_online_dates/4" do
    test "updates only the mandatory date and keeps the elective selection" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = online_course_fixture(season)
      topic = topic_fixture(course)
      mandatory1 = mandatory_date_fixture(course, %{date: ~D[2026-04-13], time: ~T[14:00:00]})
      mandatory2 = mandatory_date_fixture(course, %{date: ~D[2026-04-14], time: ~T[15:00:00]})
      elective = elective_date_fixture(course, topic)

      assert {:ok, registration} =
               Registrations.enroll_one(user, course, nil, [mandatory1.id, elective.id])

      assert {:ok, _} =
               Registrations.reschedule_online_dates(user, registration.id, %{
                 "mandatory" => mandatory2.id
               })

      selections = Courses.list_date_selections_for_registration(registration.id)
      selected_ids = MapSet.new(selections, & &1.date.id)

      assert MapSet.member?(selected_ids, mandatory2.id)
      assert MapSet.member?(selected_ids, elective.id)
      refute MapSet.member?(selected_ids, mandatory1.id)
    end

    test "allows keeping a full current date while changing the other one" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        online_course_fixture(season, %{
          max_participants: 1,
          max_per_club: 1
        })

      topic = topic_fixture(course)
      mandatory = mandatory_date_fixture(course)

      elective1 =
        elective_date_fixture(course, topic, %{date: ~D[2026-04-21], time: ~T[16:00:00]})

      elective2 =
        elective_date_fixture(course, topic, %{date: ~D[2026-04-22], time: ~T[18:00:00]})

      assert {:ok, registration} =
               Registrations.enroll_one(user, course, nil, [mandatory.id, elective1.id])

      assert {:ok, _} =
               Registrations.reschedule_online_dates(user, registration.id, %{
                 "elective" => elective2.id
               })

      selections = Courses.list_date_selections_for_registration(registration.id)
      selected_ids = MapSet.new(selections, & &1.date.id)

      assert MapSet.member?(selected_ids, mandatory.id)
      assert MapSet.member?(selected_ids, elective2.id)
    end

    test "returns not_available when moving to a full target date" do
      club1 = club_fixture()
      club2 = club_fixture()
      user1 = user_fixture(%{club_id: club1.id})
      user2 = user_fixture(%{club_id: club2.id})
      season = season_fixture()

      course =
        online_course_fixture(season, %{
          max_participants: 1,
          max_per_club: 1
        })

      topic = topic_fixture(course)
      mandatory1 = mandatory_date_fixture(course, %{date: ~D[2026-04-13], time: ~T[14:00:00]})
      mandatory2 = mandatory_date_fixture(course, %{date: ~D[2026-04-14], time: ~T[15:00:00]})

      elective1 =
        elective_date_fixture(course, topic, %{date: ~D[2026-04-21], time: ~T[16:00:00]})

      elective2 =
        elective_date_fixture(course, topic, %{date: ~D[2026-04-22], time: ~T[18:00:00]})

      assert {:ok, registration1} =
               Registrations.enroll_one(user1, course, nil, [mandatory1.id, elective1.id])

      assert {:ok, _registration2} =
               Registrations.enroll_one(user2, course, nil, [mandatory2.id, elective2.id])

      assert {:error, {:not_available, _date}} =
               Registrations.reschedule_online_dates(user1, registration1.id, %{
                 "mandatory" => mandatory2.id
               })

      selections = Courses.list_date_selections_for_registration(registration1.id)
      selected_ids = MapSet.new(selections, & &1.date.id)

      assert MapSet.member?(selected_ids, mandatory1.id)
      assert MapSet.member?(selected_ids, elective1.id)
    end

    test "returns not_found for an unenrolled registration" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = online_course_fixture(season)
      topic = topic_fixture(course)
      mandatory = mandatory_date_fixture(course)
      elective = elective_date_fixture(course, topic)

      assert {:ok, registration} =
               Registrations.enroll_one(user, course, nil, [mandatory.id, elective.id])

      assert {:ok, _} = Registrations.sign_out(course.id, user.id, admin.id)

      assert {:error, :not_found} =
               Registrations.reschedule_online_dates(user, registration.id, %{
                 "mandatory" => mandatory.id
               })
    end

    test "rejects a date from another course" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = online_course_fixture(season)
      topic = topic_fixture(course)
      mandatory = mandatory_date_fixture(course)
      elective = elective_date_fixture(course, topic)

      other_course = online_course_fixture(season, %{name: "Anderer Online-Kurs"})
      other_topic = topic_fixture(other_course, "Thema B")
      foreign_mandatory = mandatory_date_fixture(other_course, %{date: ~D[2026-04-15]})

      _foreign_elective =
        elective_date_fixture(other_course, other_topic, %{date: ~D[2026-04-23]})

      assert {:ok, registration} =
               Registrations.enroll_one(user, course, nil, [mandatory.id, elective.id])

      assert {:error, {:invalid_selection, :date_belongs_to_other_course}} =
               Registrations.reschedule_online_dates(user, registration.id, %{
                 "mandatory" => foreign_mandatory.id
               })
    end
  end

  # ── Invalid Selection ────────────────────────────────────────────────────────

  describe "enroll_one/4 - online course: ungültige Terminauswahl" do
    setup do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = online_course_fixture(season)
      topic = topic_fixture(course)
      mandatory = mandatory_date_fixture(course)
      elective = elective_date_fixture(course, topic)
      %{user: user, course: course, mandatory: mandatory, elective: elective}
    end

    test "fehler wenn kein mandatory Termin übergeben", %{
      user: user,
      course: course,
      elective: elective
    } do
      assert {:error, {:invalid_selection, _}} =
               Registrations.enroll_one(user, course, nil, [elective.id])
    end

    test "fehler wenn kein elective Termin übergeben", %{
      user: user,
      course: course,
      mandatory: mandatory
    } do
      assert {:error, {:invalid_selection, _}} =
               Registrations.enroll_one(user, course, nil, [mandatory.id])
    end

    test "fehler wenn 2 mandatory Termine übergeben", %{user: user, course: course} do
      mandatory2 = mandatory_date_fixture(course, %{date: ~D[2026-04-14]})
      mandatory1 = mandatory_date_fixture(course, %{date: ~D[2026-04-13]})

      assert {:error, {:invalid_selection, _}} =
               Registrations.enroll_one(user, course, nil, [mandatory1.id, mandatory2.id])
    end

    test "fehler wenn 2 elective Termine übergeben", %{user: user, course: course} do
      topic = topic_fixture(course, "Thema B")
      elective2 = elective_date_fixture(course, topic, %{date: ~D[2026-04-22]})
      elective1 = elective_date_fixture(course, topic, %{date: ~D[2026-04-21]})

      assert {:error, {:invalid_selection, _}} =
               Registrations.enroll_one(user, course, nil, [elective1.id, elective2.id])
    end

    test "fehler wenn Termin zu anderem Kurs gehört", %{
      user: user,
      course: course,
      mandatory: mandatory
    } do
      other_season = season_fixture()
      other_course = online_course_fixture(other_season)
      other_topic = topic_fixture(other_course)
      foreign_elective = elective_date_fixture(other_course, other_topic)

      assert {:error, {:invalid_selection, _}} =
               Registrations.enroll_one(user, course, nil, [mandatory.id, foreign_elective.id])
    end

    test "fehler wenn leere Terminliste übergeben", %{user: user, course: course} do
      assert {:error, {:invalid_selection, _}} =
               Registrations.enroll_one(user, course, nil, [])
    end

    test "fehler wenn nil als Terminliste übergeben", %{user: user, course: course} do
      assert {:error, {:invalid_selection, _}} =
               Registrations.enroll_one(user, course, nil, nil)
    end
  end

  # ── 2-Kurs-Regel ─────────────────────────────────────────────────────────────

  describe "enroll_one/4 - online course: 2-Kurs-Regel" do
    test "user mit bestehendem Präsenz-F-Kurs kann keinen Online-F-Kurs buchen" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      offline_f = course_fixture(%{season_id: season.id, type: "F", date: ~D[2026-05-01]})
      Registrations.enroll_one(user, offline_f)

      online_f = online_course_fixture(season)
      topic = topic_fixture(online_f)
      mandatory = mandatory_date_fixture(online_f)
      elective = elective_date_fixture(online_f, topic)

      assert {:error, {:not_allowed, _}} =
               Registrations.enroll_one(user, online_f, nil, [mandatory.id, elective.id])
    end

    test "user mit bestehendem Online-F-Kurs kann keinen Präsenz-F-Kurs buchen" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      online_f = online_course_fixture(season)
      topic = topic_fixture(online_f)
      mandatory = mandatory_date_fixture(online_f)
      elective = elective_date_fixture(online_f, topic)
      Registrations.enroll_one(user, online_f, nil, [mandatory.id, elective.id])

      offline_f = course_fixture(%{season_id: season.id, type: "F", date: ~D[2026-05-01]})

      assert {:error, {:not_allowed, _}} = Registrations.enroll_one(user, offline_f)
    end
  end

  # ── Normaler Kurs ignoriert Terminauswahl ────────────────────────────────────

  describe "enroll_one/4 - normaler Kurs ignoriert Terminauswahl" do
    test "F-Kurs (online=false) mit übergebenen date_ids: kein Fehler, keine selections" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          type: "F",
          date: ~D[2026-05-01],
          max_participants: 20,
          max_per_club: 6
        })

      assert {:ok, registration} = Registrations.enroll_one(user, course, nil, [999])

      assert selection_count(registration.id) == 0
    end
  end
end
