defmodule Whistle.Repo.Migrations.CreateCourseDateTopics do
  use Ecto.Migration

  def change do
    create table(:course_date_topics) do
      add :course_id, references(:courses, on_delete: :delete_all), null: false
      add :name, :text, null: false

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:course_date_topics, [:course_id])
  end
end
