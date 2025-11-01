defmodule Whistle.Repo.Migrations.CreateLicenses do
  use Ecto.Migration

  def change do
    execute """
              CREATE TYPE license_type AS ENUM (
                'N1',
                'N2',
                'N3',
                'N4',
                'L1',
                'L2',
                'L3',
                'LJ'
              )
            """,
            "DROP TYPE IF EXISTS license_type"

    create table(:licenses) do
      add :number, :integer, null: false
      add :type, :license_type, null: false
      add :season_id, references(:seasons), null: false
      add :user_id, references(:users), null: false
      add :created_by, references(:users), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:licenses, [:season_id])
    create index(:licenses, [:user_id])
    create index(:licenses, [:created_by])
  end
end
