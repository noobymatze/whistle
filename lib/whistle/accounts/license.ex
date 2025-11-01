defmodule Whistle.Accounts.License do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "licenses" do
    field :number, :integer
    field :type, Ecto.Enum, values: [:N1, :N2, :N3, :N4, :L1, :L2, :L3, :LJ]

    belongs_to :season, Whistle.Seasons.Season
    belongs_to :user, Whistle.Accounts.User
    belongs_to :created_by_user, Whistle.Accounts.User, foreign_key: :created_by

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc false
  def changeset(license, attrs) do
    license
    |> cast(attrs, [:number, :type, :season_id, :user_id, :created_by])
    |> validate_required([:number, :type, :season_id, :user_id, :created_by])
  end
end
