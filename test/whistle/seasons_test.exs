defmodule Whistle.SeasonsTest do
  use Whistle.DataCase

  alias Whistle.Seasons

  describe "seasons" do
    alias Whistle.Seasons.Season

    import Whistle.SeasonsFixtures

    @invalid_attrs %{start: nil, year: nil, start_registration: nil, end_registration: nil}

    test "list_seasons/0 returns all seasons" do
      season = season_fixture()
      assert Seasons.list_seasons() == [season]
    end

    test "current_season/1 returns the currently active season" do
      season = season_fixture()
      assert Seasons.get_current_season() == season
    end

    test "current_season/1 returns the currently active season, when there are multiple seasons" do
      season1 =
        season_fixture(%{
          start: ~D[2023-02-08],
          year: 2023,
          start_registration: nil,
          end_registration: nil
        })

      season_fixture(%{
        start: ~D[2024-02-09],
        year: 2024,
        start_registration: nil,
        end_registration: nil
      })

      {:ok, now} = DateTime.from_naive(~N[2024-02-08 14:30:00], "Etc/UTC")
      assert Seasons.get_current_season(now) == season1
    end

    test "get_season!/1 returns the season with given id" do
      season = season_fixture()
      assert Seasons.get_season!(season.id) == season
    end

    test "create_season/1 with valid data creates a season" do
      valid_attrs = %{
        start: ~D[2024-02-08],
        year: 42,
        start_registration: ~N[2024-02-08 14:30:00],
        end_registration: ~N[2024-02-08 14:30:00]
      }

      assert {:ok, %Season{} = season} = Seasons.create_season(valid_attrs)
      assert season.start == ~D[2024-02-08]
      assert season.year == 42
      assert season.start_registration == ~N[2024-02-08 14:30:00]
      assert season.end_registration == ~N[2024-02-08 14:30:00]
    end

    test "create_season/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Seasons.create_season(@invalid_attrs)
    end

    test "update_season/2 with valid data updates the season" do
      season = season_fixture()

      update_attrs = %{
        start: ~D[2024-02-09],
        year: 43,
        start_registration: ~N[2024-02-09 14:30:00],
        end_registration: ~N[2024-02-09 14:30:00]
      }

      assert {:ok, %Season{} = season} = Seasons.update_season(season, update_attrs)
      assert season.start == ~D[2024-02-09]
      assert season.year == 43
      assert season.start_registration == ~N[2024-02-09 14:30:00]
      assert season.end_registration == ~N[2024-02-09 14:30:00]
    end

    test "update_season/2 with invalid data returns error changeset" do
      season = season_fixture()
      assert {:error, %Ecto.Changeset{}} = Seasons.update_season(season, @invalid_attrs)
      assert season == Seasons.get_season!(season.id)
    end

    test "delete_season/1 deletes the season" do
      season = season_fixture()
      assert {:ok, %Season{}} = Seasons.delete_season(season)
      assert_raise Ecto.NoResultsError, fn -> Seasons.get_season!(season.id) end
    end

    test "change_season/1 returns a season changeset" do
      season = season_fixture()
      assert %Ecto.Changeset{} = Seasons.change_season(season)
    end
  end
end
