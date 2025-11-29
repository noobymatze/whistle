defmodule Whistle.Repo.Migrations.CreateRegistrations do
  use Ecto.Migration

  def change do
    create table(:registrations) do
      add :unenrolled_at, :naive_datetime
      add :course_id, references(:courses, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)
      add :registered_by, references(:users, on_delete: :nothing)
      add :unenrolled_by, references(:users, on_delete: :nothing)

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:registrations, [:course_id])
    create index(:registrations, [:user_id])
    create index(:registrations, [:registered_by])
    create index(:registrations, [:unenrolled_by])
  end
end
