defmodule Whistle.Repo.Migrations.CreateSeasons do
  use Ecto.Migration

  def change do
    create table(:seasons) do
      add :year, :integer, null: false
      add :start, :date, null: false
      add :start_registration, :naive_datetime
      add :end_registration, :naive_datetime

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end
  end
end
