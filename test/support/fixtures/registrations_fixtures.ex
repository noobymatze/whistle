defmodule Whistle.RegistrationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Whistle.Registrations` context.
  """

  import Whistle.AccountsFixtures
  import Whistle.CoursesFixtures

  @doc """
  Generate a registration.
  """
  def registration_fixture(attrs \\ %{}) do
    user = user_fixture()
    course = course_fixture()

    {:ok, registration} =
      attrs
      |> Enum.into(%{
        course_id: course.id,
        user_id: user.id,
        unenrolled_at: ~N[2024-02-08 21:11:00]
      })
      |> Whistle.Registrations.create_registration()

    registration
  end
end
