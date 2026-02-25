defmodule Whistle.Repo.Migrations.AddLicenseNumberToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :license_number, :string, null: true
    end
  end
end
