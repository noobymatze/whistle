defmodule Whistle.Repo.Migrations.RemoveEmailUniqueness do
  use Ecto.Migration

  def change do
    # Remove unique constraint on email (if it exists)
    drop_if_exists unique_index(:users, [:email])

    # Add regular index for email lookups (non-unique)
    create_if_not_exists index(:users, [:email])
  end
end
