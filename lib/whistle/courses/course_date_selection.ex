defmodule Whistle.Courses.CourseDateSelection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "course_date_selections" do
    field :registration_id, :id
    field :course_date_id, :id

    timestamps(type: :naive_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(selection, attrs) do
    selection
    |> cast(attrs, [:registration_id, :course_date_id])
    |> validate_required([:registration_id, :course_date_id])
  end
end
