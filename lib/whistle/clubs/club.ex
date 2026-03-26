defmodule Whistle.Clubs.Club do
  use Ecto.Schema
  import Ecto.Changeset

  schema "clubs" do
    field :name, :string
    field :short_name, :string
    field :association_id, :id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @doc false
  def changeset(club, attrs) do
    club
    |> cast(attrs, [:name, :short_name, :association_id])
    |> validate_required([:name, :association_id])
  end
end
