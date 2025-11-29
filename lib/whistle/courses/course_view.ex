defmodule Whistle.Courses.CourseView do
  use Ecto.Schema

  schema "courses_view" do
    field :name, :string
    field :type, :string
    field :date, :date
    field :released_at, :naive_datetime
    field :max_organizer_participants, :integer
    field :max_participants, :integer
    field :max_per_club, :integer
    field :season_id, :id
    field :organizer_id, :id
    field :organizer_name, :string
    field :participants, :integer
    field :participants_from_organizer, :integer
    field :participants_other, :integer

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
