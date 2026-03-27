defmodule Whistle.Repo.Migrations.ConvertPointsToInteger do
  use Ecto.Migration

  def change do
    alter table(:exam_questions) do
      modify :points, :integer, null: false, default: 1, from: :decimal
    end

    alter table(:exam_answers) do
      modify :awarded_points, :integer, from: :decimal
    end
  end
end
