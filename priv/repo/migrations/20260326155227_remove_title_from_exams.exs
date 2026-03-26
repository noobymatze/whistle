defmodule Whistle.Repo.Migrations.RemoveTitleFromExams do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      remove :title, :string, null: false
    end
  end
end
