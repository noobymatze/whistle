defmodule Whistle.RegistrationsTest do
  use Whistle.DataCase

  alias Whistle.Registrations

  describe "registrations" do
    alias Whistle.Registrations.Registration

    import Whistle.RegistrationsFixtures
    import Whistle.AccountsFixtures
    import Whistle.CoursesFixtures

    @invalid_attrs %{course_id: nil, user_id: nil, unenrolled_at: nil}

    test "list_registrations/0 returns all registrations" do
      registration = registration_fixture()
      assert Registrations.list_registrations() == [registration]
    end

    test "get_registration!/1 returns the registration with given id" do
      registration = registration_fixture()
      assert Registrations.get_registration!(registration.id) == registration
    end

    test "create_registration/1 with valid data creates a registration" do
      user = user_fixture()
      course = course_fixture()

      valid_attrs = %{
        course_id: course.id,
        user_id: user.id,
        unenrolled_at: ~N[2024-02-08 21:11:00]
      }

      assert {:ok, %Registration{} = registration} =
               Registrations.create_registration(valid_attrs)

      assert registration.course_id == course.id
      assert registration.user_id == user.id
      assert registration.unenrolled_at == ~N[2024-02-08 21:11:00]
    end

    test "create_registration/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Registrations.create_registration(@invalid_attrs)
    end

    test "update_registration/2 with valid data updates the registration" do
      registration = registration_fixture()
      update_attrs = %{unenrolled_at: ~N[2024-02-09 21:11:00]}

      assert {:ok, %Registration{} = registration} =
               Registrations.update_registration(registration, update_attrs)

      assert registration.unenrolled_at == ~N[2024-02-09 21:11:00]
    end

    test "update_registration/2 with invalid data returns error changeset" do
      registration = registration_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Registrations.update_registration(registration, @invalid_attrs)

      assert registration == Registrations.get_registration!(registration.id)
    end

    test "delete_registration/1 deletes the registration" do
      registration = registration_fixture()
      assert {:ok, %Registration{}} = Registrations.delete_registration(registration)
      assert_raise Ecto.NoResultsError, fn -> Registrations.get_registration!(registration.id) end
    end

    test "change_registration/1 returns a registration changeset" do
      registration = registration_fixture()
      assert %Ecto.Changeset{} = Registrations.change_registration(registration)
    end
  end
end
