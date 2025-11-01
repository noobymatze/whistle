defmodule Whistle.ClubsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Whistle.Clubs` context.
  """

  alias Whistle.AssociationsFixtures

  @doc """
  Generate a club.
  """
  def club_fixture(attrs \\ %{}) do
    association = AssociationsFixtures.association_fixture()

    {:ok, club} =
      attrs
      |> Enum.into(%{
        name: "some name",
        short_name: "some short_name",
        association_id: association.id
      })
      |> Whistle.Clubs.create_club()

    club
  end
end
