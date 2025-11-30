defmodule Whistle.Seasons do
  @moduledoc """
  The Seasons context.
  """

  import Ecto.Query, warn: false
  alias Whistle.Repo

  alias Whistle.Seasons.Season

  @doc """
  Returns the list of seasons ordered by start date descending.

  ## Examples

      iex> list_seasons()
      [%Season{}, ...]

  """
  def list_seasons do
    query = from s in Season, order_by: [desc: s.start]
    Repo.all(query)
  end

  @doc """
  Returns true if the registration of a season is open.

  """
  def is_registration_opened(season, now \\ nil) do
    now = now || Whistle.Timezone.now_local()

    case season do
      nil ->
        false

      %Season{} = season ->
        start_at = season.start_registration
        end_at = season.end_registration

        # now is already a NaiveDateTime from Whistle.Timezone.now_local()
        # Assuming naive datetimes in DB are in local timezone
        start_at != nil and NaiveDateTime.before?(start_at, now) and
          ((end_at != nil and NaiveDateTime.after?(end_at, now)) or end_at == nil)
    end
  end

  @doc """
  Returns the current seasons based on the starting date.
  """
  def get_current_season(now \\ nil) do
    now =
      cond do
        is_nil(now) -> Whistle.Timezone.today_local()
        is_struct(now, NaiveDateTime) -> NaiveDateTime.to_date(now)
        is_struct(now, DateTime) -> DateTime.to_date(now)
        true -> now
      end

    query = from s in Season, where: s.start <= ^now, order_by: [desc: s.start], limit: 1
    Repo.one(query)
  end

  @doc """
  Gets a single season.

  Raises `Ecto.NoResultsError` if the Season does not exist.

  ## Examples

      iex> get_season!(123)
      %Season{}

      iex> get_season!(456)
      ** (Ecto.NoResultsError)

  """
  def get_season!(id), do: Repo.get!(Season, id)

  @doc """
  Creates a season.

  ## Examples

      iex> create_season(%{field: value})
      {:ok, %Season{}}

      iex> create_season(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_season(attrs \\ %{}) do
    %Season{}
    |> Season.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a season.

  ## Examples

      iex> update_season(season, %{field: new_value})
      {:ok, %Season{}}

      iex> update_season(season, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_season(%Season{} = season, attrs) do
    season
    |> Season.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a season.

  ## Examples

      iex> delete_season(season)
      {:ok, %Season{}}

      iex> delete_season(season)
      {:error, %Ecto.Changeset{}}

  """
  def delete_season(%Season{} = season) do
    Repo.delete(season)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking season changes.

  ## Examples

      iex> change_season(season)
      %Ecto.Changeset{data: %Season{}}

  """
  def change_season(%Season{} = season, attrs \\ %{}) do
    Season.changeset(season, attrs)
  end
end
