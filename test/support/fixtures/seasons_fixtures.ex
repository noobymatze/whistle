defmodule Whistle.SeasonsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Whistle.Seasons` context.
  """

  @doc """
  Generate a season.
  """
  def season_fixture(attrs \\ %{}) do
    {:ok, season} =
      attrs
      |> Enum.into(%{
        end_registration: ~N[2024-02-08 14:30:00],
        start: ~D[2024-02-08],
        start_registration: ~N[2024-02-08 14:30:00],
        year: 42
      })
      |> Whistle.Seasons.create_season()

    season
  end
end
