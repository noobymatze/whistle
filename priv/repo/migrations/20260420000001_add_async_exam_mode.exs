defmodule Whistle.Repo.Migrations.AddAsyncExamMode do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :execution_mode, :string, null: false, default: "synchronous"
    end

    alter table(:exam_participants) do
      add :async_started_at, :naive_datetime
      add :async_deadline_at, :naive_datetime
    end
  end
end
