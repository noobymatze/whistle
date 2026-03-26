defmodule Whistle.Courses.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :name, :string
    field :type, :string
    field :date, :date
    field :max_participants, :integer
    field :max_per_club, :integer
    field :max_organizer_participants, :integer
    field :released_at, :naive_datetime
    field :organizer_id, :id
    field :season_id, :id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def available_types() do
    [
      {"F", "F"},
      {"J", "J"},
      {"G", "G"}
    ]
  end

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :name,
      :date,
      :max_participants,
      :max_per_club,
      :max_organizer_participants,
      :released_at,
      :organizer_id,
      :season_id,
      :type
    ])
    |> validate_required([
      :name,
      :type,
      :season_id
    ])
  end
end
