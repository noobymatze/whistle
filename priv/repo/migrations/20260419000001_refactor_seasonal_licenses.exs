defmodule Whistle.Repo.Migrations.RefactorSeasonalLicenses do
  use Ecto.Migration

  def up do
    # Recreate registrations_view reading license_number from users, not licenses.number
    execute "DROP VIEW IF EXISTS registrations_view CASCADE"

    execute """
    CREATE VIEW registrations_view AS
    SELECT oc.id            as organizer_id,
           oc.name          as organizer_name,
           oc.short_name    as organizer_short_name,
           a.id             as association_id,
           a.name           as association_name,
           r.id             as registration_id,
           r.user_id        as user_id,
           u.first_name     as user_first_name,
           u.last_name      as user_last_name,
           u.email          as user_email,
           u.birthday       as user_birthday,
           u.username       as username,
           u.club_id        as user_club_id,
           r.created_at     as registered_at,
           r.registered_by  as registered_by,
           r.unenrolled_by  as unenrolled_by,
           r.unenrolled_at  as unenrolled_at,
           cr.id            as course_id,
           cr.name          as course_name,
           cr.type          as course_type,
           cr.season_id     as season_id,
           cr.date          as course_date,
           cr.online        as course_online,
           s.year           as year,
           uc.name          as user_club_name,
           u.license_number as license_number
    FROM registrations r
    JOIN courses cr ON r.course_id = cr.id
    LEFT JOIN clubs oc ON cr.organizer_id = oc.id
    JOIN seasons s ON cr.season_id = s.id
    JOIN users u ON r.user_id = u.id
    JOIN clubs uc ON uc.id = u.club_id
    LEFT JOIN associations a ON oc.association_id = a.id
    """

    # Now safe to drop the number column
    alter table(:licenses) do
      remove :number, :integer
    end

    # Seasonal licenses are unique per user per season
    create unique_index(:licenses, [:user_id, :season_id])

    # Track whether the participant is eligible for manual L1 review
    alter table(:exam_participants) do
      add :l1_review_eligible, :boolean, default: false, null: false
    end
  end

  def down do
    alter table(:exam_participants) do
      remove :l1_review_eligible, :boolean
    end

    drop unique_index(:licenses, [:user_id, :season_id])

    alter table(:licenses) do
      add :number, :integer, null: false, default: 0
    end

    execute "DROP VIEW IF EXISTS registrations_view CASCADE"

    execute """
    CREATE VIEW registrations_view AS
    SELECT oc.id            as organizer_id,
           oc.name          as organizer_name,
           oc.short_name    as organizer_short_name,
           a.id             as association_id,
           a.name           as association_name,
           r.id             as registration_id,
           r.user_id        as user_id,
           u.first_name     as user_first_name,
           u.last_name      as user_last_name,
           u.email          as user_email,
           u.birthday       as user_birthday,
           u.username       as username,
           u.club_id        as user_club_id,
           r.created_at     as registered_at,
           r.registered_by  as registered_by,
           r.unenrolled_by  as unenrolled_by,
           r.unenrolled_at  as unenrolled_at,
           cr.id            as course_id,
           cr.name          as course_name,
           cr.type          as course_type,
           cr.season_id     as season_id,
           cr.date          as course_date,
           cr.online        as course_online,
           s.year           as year,
           uc.name          as user_club_name,
           l.number         as license_number
    FROM registrations r
    JOIN courses cr ON r.course_id = cr.id
    LEFT JOIN clubs oc ON cr.organizer_id = oc.id
    JOIN seasons s ON cr.season_id = s.id
    JOIN users u ON r.user_id = u.id
    JOIN clubs uc ON uc.id = u.club_id
    LEFT JOIN associations a ON oc.association_id = a.id
    LEFT JOIN licenses l ON s.id = l.season_id AND l.user_id = u.id
    """
  end
end
