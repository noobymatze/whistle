defmodule Whistle.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :email, :citext, null: false
      add :username, :text, null: false
      add :first_name, :text
      add :last_name, :text
      add :mobile, :text
      add :phone, :text
      add :birthday, :date
      add :club_id, references(:clubs)
      add :role, :text, null: false, default: "USER"
      add :hashed_password, :string
      add :confirmed_at, :naive_datetime
      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
