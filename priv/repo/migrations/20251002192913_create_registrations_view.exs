defmodule Whistle.Repo.Migrations.CreateRegistrationsView do
  use Ecto.Migration

  def change do
    execute """
              CREATE VIEW registrations_view AS
              SELECT c.id            as organizer_id,
                     c.name          as organizer_name,
                     c.short_name    as organizer_short_name,
                     a.id            as association_id,
                     a.name          as association_name,
                     r.user_id       as user_id,
                     u.first_name    as user_first_name,
                     u.last_name     as user_last_name,
                     u.email         as user_email,
                     u.birthday      as user_birthday,
                     u.username      as username,
                     u.club_id       as user_club_id,
                     r.created_at    as registered_at,
                     r.registered_by as registered_by,
                     r.unenrolled_by as unenrolled_by,
                     r.unenrolled_at as unenrolled_at,
                     cr.id           as course_id,
                     cr.name         as course_name,
                     cr.season_id    as season_id,
                     cr.date         as course_date,
                     s.year          as year,
                     uc.name         as user_club_name,
                     l.number        as license_number
              FROM registrations r
              JOIN courses cr ON r.course_id = cr.id
              JOIN clubs c ON cr.organizer_id = c.id
              JOIN seasons s ON cr.season_id = s.id
              JOIN users u ON r.user_id = u.id
              JOIN clubs uc ON uc.id = u.club_id
              JOIN associations a ON c.association_id = a.id
              LEFT JOIN licenses l ON s.id = l.season_id and l.user_id = u.id
            """,
            "DROP VIEW IF EXISTS registrations_view CASCADE"
  end
end
