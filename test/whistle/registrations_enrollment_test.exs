defmodule Whistle.RegistrationsEnrollmentTest do
  use Whistle.DataCase

  alias Whistle.Registrations

  import Whistle.AccountsFixtures
  import Whistle.ClubsFixtures
  import Whistle.CoursesFixtures
  import Whistle.SeasonsFixtures

  describe "enroll_one/3 - basic enrollment (happy path)" do
    test "successful single course enrollment" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:ok, registration} = Registrations.enroll_one(user, course)
      assert registration.course_id == course.id

      # Verify registration was created
      registrations = Registrations.list_registrations_view(season_id: season.id)
      assert length(registrations) == 1
      assert hd(registrations).user_id == user.id
      assert hd(registrations).course_id == course.id
      assert is_nil(hd(registrations).unenrolled_at)
    end

    test "successful multi-course enrollment (2 courses)" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course1 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          type: "F",
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      course2 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          type: "G",
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert [{:ok, _}, {:ok, _}] = Registrations.enroll(user, [course1, course2])

      # Verify both registrations were created
      registrations = Registrations.list_registrations_view(season_id: season.id)
      assert length(registrations) == 2
      assert Enum.all?(registrations, &is_nil(&1.unenrolled_at))
    end

    test "enrollment with registered_by tracking" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:ok, _} = Registrations.enroll_one(user, course, admin.id)

      # Verify registered_by is tracked
      [registration] = Registrations.list_registrations()
      assert registration.registered_by == admin.id
    end
  end

  describe "enroll_one/3 - two-course limit" do
    test "reject enrollment when user already has 2 courses" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      # User already enrolled in 2 courses
      course1 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      course2 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      Registrations.enroll(user, [course1, course2])

      # Try to enroll in 3rd course
      course3 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:error, {:not_allowed, _course}} =
               Registrations.enroll_one(user, course3)
    end

    test "allow enrollment when user has 1 course, enrolling in 1 more" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      # User enrolled in 1 course
      course1 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      Registrations.enroll_one(user, course1)

      # Enroll in 2nd course
      course2 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:ok, _} = Registrations.enroll_one(user, course2)

      registrations = Registrations.list_registrations_view(season_id: season.id)
      assert length(registrations) == 2
    end

    test "different seasons don't interfere with limits" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season1 = season_fixture(%{year: 2024})
      season2 = season_fixture(%{year: 2025})

      # User has 2 courses in season 1
      course1 =
        course_fixture(%{
          season_id: season1.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      course2 =
        course_fixture(%{
          season_id: season1.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      Registrations.enroll(user, [course1, course2])

      # Enroll in course in season 2
      course3 =
        course_fixture(%{
          season_id: season2.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:ok, _} = Registrations.enroll_one(user, course3)

      assert length(Registrations.list_registrations_view(season_id: season1.id)) == 2
      assert length(Registrations.list_registrations_view(season_id: season2.id)) == 1
    end

    test "unenrolled courses don't count toward limit" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()

      # User has 2 registrations, but both are unenrolled
      course1 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      course2 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      Registrations.enroll(user, [course1, course2])
      Registrations.sign_out(course1.id, user.id, admin.id)
      Registrations.sign_out(course2.id, user.id, admin.id)

      # Enroll in new course
      course3 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:ok, _} = Registrations.enroll_one(user, course3)
    end
  end

  describe "enroll_one/3 - duplicate registration" do
    test "reject duplicate enrollment in same course" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # First enrollment succeeds
      assert {:ok, _} = Registrations.enroll_one(user, course)

      # Second enrollment fails (returns :not_allowed because user is already registered)
      assert {:error, {:not_allowed, _course}} =
               Registrations.enroll_one(user, course)
    end

    test "multi-enrollment with one duplicate" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course1 =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # Enroll in course1
      Registrations.enroll_one(user, course1)

      # Try to enroll in course1 again (duplicate) as a single enrollment
      # This tests duplicate detection without hitting the 2-course limit
      result = Registrations.enroll_one(user, course1)

      # Should return not_allowed error (duplicate registration)
      assert {:error, {:not_allowed, _}} = result

      # Verify: still only 1 registration
      registrations = Registrations.list_registrations_view(season_id: season.id)
      assert length(registrations) == 1
    end
  end

  describe "enroll_one/3 - capacity constraints" do
    test "organizer club member enrollment before release" do
      organizer_club = club_fixture()
      user = user_fixture(%{club_id: organizer_club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          # Not released yet
          released_at: nil
        })

      # Create 4 existing organizer registrations
      for _ <- 1..4 do
        other_user = user_fixture(%{club_id: organizer_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: other_user.id})
      end

      # 5th organizer should succeed (one spot left)
      assert {:ok, _} = Registrations.enroll_one(user, course)
    end

    test "organizer club capacity reached before release" do
      organizer_club = club_fixture()
      user = user_fixture(%{club_id: organizer_club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: nil
        })

      # Create 5 existing organizer registrations (limit reached)
      for _ <- 1..5 do
        other_user = user_fixture(%{club_id: organizer_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: other_user.id})
      end

      # 6th organizer should fail
      assert {:error, {:not_available, _}} =
               Registrations.enroll_one(user, course)
    end

    test "non-organizer enrollment allowed before release up to calculated limit" do
      organizer_club = club_fixture()
      other_club = club_fixture()
      user = user_fixture(%{club_id: other_club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          # Not released
          released_at: nil
        })

      # Create 2 organizer registrations
      for _ <- 1..2 do
        organizer_user = user_fixture(%{club_id: organizer_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: organizer_user.id})
      end

      # Non-organizer should be able to enroll
      # max_for_others = 20 - 5 = 15, current = 0
      assert {:ok, _} = Registrations.enroll_one(user, course)
    end

    test "non-organizer enrollment after release" do
      organizer_club = club_fixture()
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          # Released
          released_at: DateTime.utc_now()
        })

      # Create 3 organizer registrations (using only 3 of 5 reserved)
      for _ <- 1..3 do
        organizer_user = user_fixture(%{club_id: organizer_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: organizer_user.id})
      end

      # Create 10 non-organizer registrations from different clubs
      # We need at least 4 clubs to have 10 users (3 per club max, some with 2)
      clubs = for _ <- 1..5, do: club_fixture()

      for i <- 1..10 do
        # Distribute across clubs (2 per club for 5 clubs = 10 users)
        club = Enum.at(clubs, rem(i, 5))
        other_user = user_fixture(%{club_id: club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: other_user.id})
      end

      # Create a new user from first club (which has 2 users, under the limit of 3)
      user = user_fixture(%{club_id: hd(clubs).id})

      # After release: max_for_others = 20 - 3 = 17
      # Current non-organizers: 10 < 17, and user's club has only 2 users (under limit of 3)
      # So enrollment should succeed
      assert {:ok, _} = Registrations.enroll_one(user, course)
    end

    test "total capacity reached after release" do
      organizer_club = club_fixture()
      other_club = club_fixture()
      user = user_fixture(%{club_id: other_club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # Create 5 organizer registrations
      for _ <- 1..5 do
        organizer_user = user_fixture(%{club_id: organizer_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: organizer_user.id})
      end

      # Create 15 non-organizer registrations (total = 20)
      for _ <- 1..15 do
        other_user = user_fixture(%{club_id: other_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: other_user.id})
      end

      # Total capacity reached
      assert {:error, {:not_available, _}} =
               Registrations.enroll_one(user, course)
    end

    test "per-club limit enforcement" do
      organizer_club = club_fixture()
      other_club = club_fixture()
      user = user_fixture(%{club_id: other_club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # Create 2 organizer registrations
      for _ <- 1..2 do
        organizer_user = user_fixture(%{club_id: organizer_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: organizer_user.id})
      end

      # Create 3 registrations from other_club (limit reached for that club)
      for _ <- 1..3 do
        club_user = user_fixture(%{club_id: other_club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: club_user.id})
      end

      # 4th user from same club should fail
      assert {:error, {:not_available, _}} =
               Registrations.enroll_one(user, course)
    end

    test "per-club limit allows enrollment for different club" do
      organizer_club = club_fixture()
      club2 = club_fixture()
      club3 = club_fixture()
      user = user_fixture(%{club_id: club3.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # Club 2 reaches its limit
      for _ <- 1..3 do
        club2_user = user_fixture(%{club_id: club2.id})
        Registrations.create_registration(%{course_id: course.id, user_id: club2_user.id})
      end

      # User from club 3 should succeed (different club)
      assert {:ok, _} = Registrations.enroll_one(user, course)
    end
  end

  describe "enroll_one/3 - re-enrollment" do
    test "re-enroll previously unenrolled user" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # Initial enrollment
      {:ok, _} = Registrations.enroll_one(user, course)

      # Unenroll
      {:ok, _} = Registrations.sign_out(course.id, user.id, admin.id)

      # Re-enroll
      assert {:ok, _} = Registrations.enroll_one(user, course)

      # Should only have one registration (reused)
      registrations = Registrations.list_registrations()
      assert length(registrations) == 1

      registration = hd(registrations)
      assert is_nil(registration.unenrolled_at)
      assert is_nil(registration.unenrolled_by)
    end

    test "re-enrollment respects capacity limits" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 5,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: nil
        })

      # User enrolls and then unenrolls
      {:ok, _} = Registrations.enroll_one(user, course)
      {:ok, _} = Registrations.sign_out(course.id, user.id, admin.id)

      # Fill the course to capacity with other users
      for _ <- 1..5 do
        other_user = user_fixture(%{club_id: club.id})
        Registrations.create_registration(%{course_id: course.id, user_id: other_user.id})
      end

      # Re-enrollment should fail due to capacity
      assert {:error, {:not_available, _}} =
               Registrations.enroll_one(user, course)
    end

    test "unenrolled registrations excluded from capacity calculations" do
      club = club_fixture()
      new_user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 5,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: nil
        })

      # Fill to capacity
      users =
        for _ <- 1..5 do
          u = user_fixture(%{club_id: club.id})
          Registrations.create_registration(%{course_id: course.id, user_id: u.id})
          u
        end

      # Unenroll one user
      [user_to_unenroll | _] = users
      Registrations.sign_out(course.id, user_to_unenroll.id, admin.id)

      # New user should be able to enroll
      assert {:ok, _} = Registrations.enroll_one(new_user, course)
    end
  end

  describe "get_emails_for_course/1" do
    test "retrieve emails for enrolled users" do
      club = club_fixture()
      season = season_fixture()
      course = course_fixture(%{season_id: season.id, organizer_id: club.id})

      user1 = user_fixture(%{club_id: club.id, email: "user1@test.com"})
      user2 = user_fixture(%{club_id: club.id, email: "user2@test.com"})
      user3 = user_fixture(%{club_id: club.id, email: "user3@test.com"})

      Registrations.create_registration(%{course_id: course.id, user_id: user1.id})
      Registrations.create_registration(%{course_id: course.id, user_id: user2.id})
      Registrations.create_registration(%{course_id: course.id, user_id: user3.id})

      emails = Registrations.get_emails_for_course(course.id)
      assert length(emails) == 3
      assert "user1@test.com" in emails
      assert "user2@test.com" in emails
      assert "user3@test.com" in emails
    end

    test "exclude unenrolled users from email list" do
      club = club_fixture()
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()
      course = course_fixture(%{season_id: season.id, organizer_id: club.id})

      user1 = user_fixture(%{club_id: club.id, email: "user1@test.com"})
      user2 = user_fixture(%{club_id: club.id, email: "user2@test.com"})
      user3 = user_fixture(%{club_id: club.id, email: "user3@test.com"})

      Registrations.create_registration(%{course_id: course.id, user_id: user1.id})
      Registrations.create_registration(%{course_id: course.id, user_id: user2.id})
      Registrations.create_registration(%{course_id: course.id, user_id: user3.id})

      # Unenroll user2
      Registrations.sign_out(course.id, user2.id, admin.id)

      emails = Registrations.get_emails_for_course(course.id)
      assert length(emails) == 2
      assert "user1@test.com" in emails
      assert "user3@test.com" in emails
      refute "user2@test.com" in emails
    end

    test "empty course returns empty list" do
      club = club_fixture()
      season = season_fixture()
      course = course_fixture(%{season_id: season.id, organizer_id: club.id})

      emails = Registrations.get_emails_for_course(course.id)
      assert emails == []
    end
  end

  describe "edge cases and error handling" do
    test "enroll with empty course list" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})

      assert [] = Registrations.enroll(user, [])
    end

    test "enrollment with nil club_id" do
      user = user_fixture(%{club_id: nil})
      season = season_fixture()
      organizer_club = club_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # User without club should be treated as non-organizer
      # and should be able to enroll if capacity allows
      assert {:ok, _} = Registrations.enroll_one(user, course)
    end
  end

  describe "integration tests - multi-step scenarios" do
    test "full lifecycle - enroll, unenroll, re-enroll" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      admin = user_fixture(%{club_id: club.id})
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      # Step 1: Enroll
      assert {:ok, _} = Registrations.enroll_one(user, course)
      [reg1] = Registrations.list_registrations()
      assert is_nil(reg1.unenrolled_at)

      # Step 2: Unenroll
      assert {:ok, unenrolled_reg} = Registrations.sign_out(course.id, user.id, admin.id)
      assert not is_nil(unenrolled_reg.unenrolled_at)
      assert unenrolled_reg.unenrolled_by == admin.id

      # Step 3: Re-enroll
      assert {:ok, _} = Registrations.enroll_one(user, course)

      # Should still be only one registration
      registrations = Registrations.list_registrations()
      assert length(registrations) == 1

      final_reg = hd(registrations)
      assert is_nil(final_reg.unenrolled_at)
      assert is_nil(final_reg.unenrolled_by)
    end

    test "multi-user enrollment fills course to capacity" do
      organizer_club = club_fixture()
      other_club1 = club_fixture()
      other_club2 = club_fixture()
      season = season_fixture()

      course =
        course_fixture(%{
          season_id: season.id,
          organizer_id: organizer_club.id,
          max_participants: 5,
          max_organizer_participants: 2,
          max_per_club: 2,
          released_at: DateTime.utc_now()
        })

      # 2 organizer users
      organizer_users =
        for _ <- 1..2 do
          user_fixture(%{club_id: organizer_club.id})
        end

      # 2 users from other_club1
      club1_users =
        for _ <- 1..2 do
          user_fixture(%{club_id: other_club1.id})
        end

      # 1 user from other_club2
      club2_user = user_fixture(%{club_id: other_club2.id})

      # Enroll organizer users (should succeed)
      for user <- organizer_users do
        assert {:ok, _} = Registrations.enroll_one(user, course)
      end

      # Enroll club1 users (should succeed - 2 spots left, club limit allows 2)
      for user <- club1_users do
        assert {:ok, _} = Registrations.enroll_one(user, course)
      end

      # Enroll club2 user (should succeed - 1 spot left)
      assert {:ok, _} = Registrations.enroll_one(club2_user, course)

      # Total: 5 enrolled (capacity reached)
      # Try to enroll 6th user
      user6 = user_fixture(%{club_id: other_club2.id})

      assert {:error, {:not_available, _}} =
               Registrations.enroll_one(user6, course)
    end

    test "season boundary - enrollments don't cross seasons" do
      club = club_fixture()
      user = user_fixture(%{club_id: club.id})
      season1 = season_fixture(%{year: 2024})
      season2 = season_fixture(%{year: 2025})

      # User has 2 courses in season 1
      course1 =
        course_fixture(%{
          season_id: season1.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      course2 =
        course_fixture(%{
          season_id: season1.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      Registrations.enroll(user, [course1, course2])

      # Try to enroll in 3rd course in season 1 (should fail - 2-course limit)
      course3_s1 =
        course_fixture(%{
          season_id: season1.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:error, {:not_allowed, _}} =
               Registrations.enroll_one(user, course3_s1)

      # Try to enroll in course in season 2 (should succeed)
      course1_s2 =
        course_fixture(%{
          season_id: season2.id,
          organizer_id: club.id,
          max_participants: 20,
          max_organizer_participants: 5,
          max_per_club: 3,
          released_at: DateTime.utc_now()
        })

      assert {:ok, _} = Registrations.enroll_one(user, course1_s2)

      # Verify counts
      assert length(Registrations.list_registrations_view(season_id: season1.id)) == 2
      assert length(Registrations.list_registrations_view(season_id: season2.id)) == 1
    end
  end
end
