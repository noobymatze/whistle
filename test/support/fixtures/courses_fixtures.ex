defmodule Whistle.CoursesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Whistle.Courses` context.
  """

  alias Whistle.SeasonsFixtures
  alias Whistle.ClubsFixtures

  @doc """
  Generate a course.
  """
  def course_fixture(attrs \\ %{}) do
    # Only create defaults if not provided in attrs
    default_attrs = %{}

    default_attrs =
      case Map.get(attrs, :season_id) do
        nil ->
          season = SeasonsFixtures.season_fixture()
          Map.put(default_attrs, :season_id, season.id)

        _ ->
          default_attrs
      end

    default_attrs =
      case Map.get(attrs, :organizer_id) do
        nil ->
          club = ClubsFixtures.club_fixture()
          Map.put(default_attrs, :organizer_id, club.id)

        _ ->
          default_attrs
      end

    {:ok, course} =
      attrs
      |> Enum.into(default_attrs)
      |> Enum.into(%{
        date: ~D[2024-02-08],
        max_organizer_participants: 42,
        max_participants: 42,
        max_per_club: 42,
        name: "some name",
        released_at: ~N[2024-02-08 18:45:00],
        type: "some type"
      })
      |> Whistle.Courses.create_course()

    course
  end
end
