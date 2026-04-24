defmodule Whistle.Registrations.Enrollment do
  @moduledoc """
  Business logic for validating course registration eligibility.
  """

  import Ecto.Query, warn: false

  alias Whistle.Accounts.User
  alias Whistle.Courses.Course
  alias Whistle.Registrations.Registration
  alias Whistle.Repo

  @doc """
  Checks if a seat is available for the user for the given course.

  This accounts for organizer limits, course release status, and per-club
  limits.
  """
  def seat_available?(%User{} = user, course, course_registrations) when is_struct(course) do
    {from_organizer, others} = group_by_organizer(course_registrations, course)

    from_organizer_and_allowed? =
      user.club_id == course.organizer_id &&
        length(from_organizer) < course.max_organizer_participants &&
        course.max_organizer_participants > 0

    max =
      course.max_participants -
        if course.released_at do
          length(from_organizer)
        else
          course.max_organizer_participants
        end

    others_by_club = Enum.group_by(others, & &1.user_club_id)
    user_club_count = length(Map.get(others_by_club, user.club_id, []))

    from_others_and_allowed? =
      user.club_id != course.organizer_id &&
        length(others) < max &&
        max > 0 &&
        user_club_count < course.max_per_club

    from_others_and_allowed? or from_organizer_and_allowed?
  end

  @doc """
  Checks if the user is allowed to participate in the given course.
  """
  def allowed?(%User{} = user, course) when is_struct(course) do
    query =
      from r in Registration,
        join: c in Course,
        on: c.id == r.course_id,
        where:
          r.user_id == ^user.id and c.season_id == ^course.season_id and is_nil(r.unenrolled_at)

    registrations = Repo.all(query)

    cond do
      length(registrations) >= 2 ->
        false

      Enum.any?(registrations, fn r -> r.course_id == course.id end) ->
        false

      course.type == "F" and
          Enum.any?(registrations, fn r ->
            c = Repo.get!(Course, r.course_id)
            c.type == "F"
          end) ->
        false

      true ->
        true
    end
  end

  defp group_by_organizer(course_registrations, %Course{} = course) do
    result =
      course_registrations
      |> Enum.group_by(fn r -> r.user_club_id == course.organizer_id end)

    {Map.get(result, true, []), Map.get(result, false, [])}
  end
end
