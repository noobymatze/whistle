defmodule Whistle.Registrations.Registration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "registrations" do
    field :unenrolled_at, :naive_datetime
    field :course_id, :id
    field :user_id, :id
    field :registered_by, :id
    field :unenrolled_by, :id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def changeset(registration, attrs) do
    registration
    |> cast(attrs, [:course_id, :user_id, :registered_by, :unenrolled_at, :unenrolled_by])
    |> validate_required([:course_id, :user_id])
  end
end
