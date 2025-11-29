defmodule Whistle.Repo.Migrations.CreateCourses do
  use Ecto.Migration

  def change do
    create table(:courses) do
      add :name, :text, null: false
      add :date, :date
      add :max_participants, :integer, default: 20
      add :max_per_club, :integer, default: 6
      add :max_organizer_participants, :integer, default: 6
      add :released_at, :naive_datetime
      add :type, :text
      add :organizer_id, references(:clubs, on_delete: :nothing)
      add :season_id, references(:seasons, on_delete: :nothing)

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:courses, [:organizer_id])
    create index(:courses, [:season_id])
  end
end
