defmodule Whistle.Repo.Migrations.ReplacePassPercentageWithThresholds do
  use Ecto.Migration

  def change do
    # Update course_type_question_distributions
    alter table(:course_type_question_distributions) do
      add :l1_threshold, :integer
      add :l2_threshold, :integer
      add :l3_threshold, :integer
      add :pass_threshold, :integer
      remove :pass_percentage, :integer, default: 75, null: false
    end

    # Update exams (snapshot of distribution at creation time)
    alter table(:exams) do
      add :l1_threshold, :integer
      add :l2_threshold, :integer
      add :l3_threshold, :integer
      add :pass_threshold, :integer
      remove :pass_percentage, :integer, null: false
    end
  end
end
