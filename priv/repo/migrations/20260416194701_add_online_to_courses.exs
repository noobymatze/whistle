defmodule Whistle.Repo.Migrations.AddOnlineToCourses do
  use Ecto.Migration

  def up do
    alter table(:courses) do
      add :online, :boolean, null: false, default: false
    end

    # Fix any existing courses without a date — set them to online=true so the
    # CHECK constraint below is satisfied. (These are incomplete test/dev records.)
    execute "UPDATE courses SET online = true WHERE date IS NULL"

    create constraint(:courses, :check_date_online,
             check: "(online = true AND date IS NULL) OR (online = false AND date IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:courses, :check_date_online)

    alter table(:courses) do
      remove :online
    end
  end
end
