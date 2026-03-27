defmodule Whistle.Repo.Migrations.AddExamOutcomeToParticipants do
  use Ecto.Migration

  def change do
    alter table(:exam_participants) do
      add :achieved_points, :integer
      add :max_points, :integer
      add :exam_outcome, :string
    end
  end
end
