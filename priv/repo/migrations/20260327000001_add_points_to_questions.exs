defmodule Whistle.Repo.Migrations.AddPointsToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :points, :integer, null: false, default: 1
    end
  end
end
