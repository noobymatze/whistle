defmodule Whistle.Repo.Migrations.MakeUsernameUnique do
  use Ecto.Migration

  def change do
    create unique_index(:users, [:username])
  end
end
