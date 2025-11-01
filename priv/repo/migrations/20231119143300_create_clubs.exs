defmodule Whistle.Repo.Migrations.CreateClubs do
  use Ecto.Migration

  def change do
    create table(:clubs) do
      add :name, :text, null: false
      add :short_name, :text
      add :association_id, references(:associations, on_delete: :nothing)

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create index(:clubs, [:association_id])
  end
end
