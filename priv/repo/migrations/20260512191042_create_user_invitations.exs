defmodule Whistle.Repo.Migrations.CreateUserInvitations do
  use Ecto.Migration

  def change do
    create table(:user_invitations) do
      add :email, :citext, null: false
      add :code_hash, :binary, null: false
      add :invited_by_user_id, references(:users, on_delete: :nilify_all)
      add :club_id, references(:clubs, on_delete: :nilify_all)
      add :expires_at, :naive_datetime, null: false
      add :accepted_at, :naive_datetime
      add :revoked_at, :naive_datetime

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:user_invitations, [:email])
    create index(:user_invitations, [:invited_by_user_id])
    create index(:user_invitations, [:club_id])
    create unique_index(:user_invitations, [:code_hash])
  end
end
