defmodule Whistle.Repo.Migrations.CreatePendingUsers do
  use Ecto.Migration

  def change do
    create table(:pending_users) do
      add :email, :citext, null: false
      add :username, :text, null: false
      add :first_name, :text, null: false
      add :last_name, :text, null: false
      add :mobile, :text
      add :phone, :text
      add :birthday, :date, null: false
      add :hashed_password, :string, null: false
      add :confirmation_token_hash, :binary, null: false
      add :expires_at, :naive_datetime, null: false

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:pending_users, [:email])
    create unique_index(:pending_users, [:username])
    create unique_index(:pending_users, [:confirmation_token_hash])
  end
end
