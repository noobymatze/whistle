defmodule Whistle.Associations.Association do
  use Ecto.Schema
  import Ecto.Changeset

  schema "associations" do
    field :name, :string

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @doc false
  def changeset(association, attrs) do
    association
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
