defmodule Whistle.Seasons.Season do
  use Ecto.Schema
  import Ecto.Changeset

  schema "seasons" do
    field :start, :date
    field :year, :integer
    field :start_registration, :naive_datetime
    field :end_registration, :naive_datetime

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @doc false
  def changeset(season, attrs) do
    season
    |> cast(attrs, [:year, :start, :start_registration, :end_registration])
    |> validate_required([:year, :start])
  end
end
