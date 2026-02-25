defmodule Whistle.Accounts.UserView do
  use Ecto.Schema

  schema "users_view" do
    field :email, :string
    field :username, :string
    field :first_name, :string
    field :last_name, :string
    field :mobile, :string
    field :phone, :string
    field :birthday, :date
    field :role, :string
    field :confirmed_at, :naive_datetime
    field :club_id, :id
    field :license_number, :string
    field :club_name, :string
    field :club_short_name, :string

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
