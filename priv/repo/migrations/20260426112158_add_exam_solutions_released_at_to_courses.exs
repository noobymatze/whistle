defmodule Whistle.Repo.Migrations.AddExamSolutionsReleasedAtToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :exam_solutions_released_at, :naive_datetime
    end
  end
end
