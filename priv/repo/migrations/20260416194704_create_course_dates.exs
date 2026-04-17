defmodule Whistle.Repo.Migrations.CreateCourseDates do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE course_date_kind AS ENUM ('mandatory', 'elective')",
            "DROP TYPE course_date_kind"

    create table(:course_dates) do
      add :course_id, references(:courses, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :time, :time, null: false
      add :kind, :course_date_kind, null: false
      add :course_date_topic_id, references(:course_date_topics, on_delete: :delete_all)

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:course_dates, [:course_id])
    create index(:course_dates, [:course_date_topic_id])
  end
end
