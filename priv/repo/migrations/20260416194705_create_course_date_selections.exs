defmodule Whistle.Repo.Migrations.CreateCourseDateSelections do
  use Ecto.Migration

  def change do
    create table(:course_date_selections) do
      add :registration_id, references(:registrations, on_delete: :delete_all), null: false
      add :course_date_id, references(:course_dates, on_delete: :delete_all), null: false

      timestamps(type: :naive_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:course_date_selections, [:registration_id])
    create index(:course_date_selections, [:course_date_id])
  end
end
