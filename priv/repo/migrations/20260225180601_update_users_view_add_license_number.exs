defmodule Whistle.Repo.Migrations.UpdateUsersViewAddLicenseNumber do
  use Ecto.Migration

  def up do
    execute "DROP VIEW IF EXISTS users_view"

    execute """
    CREATE VIEW users_view AS
    SELECT u.id                 as id,
           u.email              as email,
           u.username           as username,
           u.first_name         as first_name,
           u.last_name          as last_name,
           u.mobile             as mobile,
           u.phone              as phone,
           u.birthday           as birthday,
           u.role               as role,
           u.confirmed_at       as confirmed_at,
           u.club_id            as club_id,
           u.license_number     as license_number,
           u.created_at         as created_at,
           u.updated_at         as updated_at,
           cl.name              as club_name,
           cl.short_name        as club_short_name
    FROM users u
    LEFT JOIN clubs cl ON u.club_id = cl.id
    """
  end

  def down do
    execute "DROP VIEW IF EXISTS users_view"

    execute """
    CREATE VIEW users_view AS
    SELECT u.id                 as id,
           u.email              as email,
           u.username           as username,
           u.first_name         as first_name,
           u.last_name          as last_name,
           u.mobile             as mobile,
           u.phone              as phone,
           u.birthday           as birthday,
           u.role               as role,
           u.confirmed_at       as confirmed_at,
           u.club_id            as club_id,
           u.created_at         as created_at,
           u.updated_at         as updated_at,
           cl.name              as club_name,
           cl.short_name        as club_short_name
    FROM users u
    LEFT JOIN clubs cl ON u.club_id = cl.id
    """
  end
end
