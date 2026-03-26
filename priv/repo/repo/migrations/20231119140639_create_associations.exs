defmodule Whistle.Repo.Migrations.CreateAssociations do
  use Ecto.Migration

  def change do
    create table(:associations) do
      add :name, :text

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end
  end
end
