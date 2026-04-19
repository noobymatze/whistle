defmodule Whistle.Repo.Migrations.UpdateViewsForOnlineCourses do
  use Ecto.Migration

  def up do
    execute "DROP VIEW IF EXISTS courses_view"

    execute """
    CREATE VIEW courses_view AS
    WITH registrations_per_course AS (
        SELECT r.course_id,
               COUNT(*) as participants,
               COUNT(*) FILTER (WHERE u.club_id = c.organizer_id) AS participants_from_organizer,
               COUNT(*) FILTER (WHERE u.club_id <> c.organizer_id OR c.organizer_id IS NULL) AS participants_other
        FROM registrations r
        JOIN courses c ON r.course_id = c.id
        JOIN users u ON r.user_id = u.id
        WHERE r.unenrolled_at IS NULL
        GROUP BY r.course_id
    )
    SELECT c.id                                          as id,
           c.name                                        as name,
           c.type                                        as type,
           c.date                                        as date,
           c.online                                      as online,
           c.released_at                                 as released_at,
           c.max_organizer_participants                  as max_organizer_participants,
           c.max_per_club                                as max_per_club,
           c.max_participants                            as max_participants,
           c.season_id                                   as season_id,
           c.created_at                                  as created_at,
           c.updated_at                                  as updated_at,
           cl.id                                         as organizer_id,
           cl.name                                       as organizer_name,
           COALESCE(rpc.participants, 0)                 as participants,
           COALESCE(rpc.participants_from_organizer, 0)  as participants_from_organizer,
           COALESCE(rpc.participants_other, 0)           as participants_other
    FROM courses c
    LEFT JOIN clubs cl ON c.organizer_id = cl.id
    LEFT JOIN registrations_per_course rpc ON rpc.course_id = c.id
    """

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

  def down do
    execute "DROP VIEW IF EXISTS registrations_view CASCADE"

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
    """

    execute "DROP VIEW IF EXISTS courses_view"

    execute """
    CREATE OR REPLACE VIEW courses_view AS
    WITH registrations_per_course AS (
        SELECT r.course_id,
               COUNT(*) as participants,
               COUNT(*) FILTER (WHERE u.club_id = c.organizer_id) AS participants_from_organizer,
               COUNT(*) FILTER (WHERE u.club_id <> c.organizer_id) AS participants_other
        FROM registrations r
        JOIN courses c ON r.course_id = c.id
        JOIN users u ON r.user_id = u.id
        WHERE r.unenrolled_at IS NULL
        GROUP BY r.course_id
    )
    SELECT c.id                                          as id,
           c.name                                        as name,
           c.type                                        as type,
           c.date                                        as date,
           c.released_at                                 as released_at,
           c.max_organizer_participants                  as max_organizer_participants,
           c.max_per_club                                as max_per_club,
           c.max_participants                            as max_participants,
           c.season_id                                   as season_id,
           c.created_at                                  as created_at,
           c.updated_at                                  as updated_at,
           cl.id                                         as organizer_id,
           cl.name                                       as organizer_name,
           COALESCE(rpc.participants, 0)                 as participants,
           COALESCE(rpc.participants_from_organizer, 0)  as participants_from_organizer,
           COALESCE(rpc.participants_other, 0)           as participants_other
    FROM courses c
    JOIN clubs cl ON c.organizer_id = cl.id
    LEFT JOIN registrations_per_course rpc ON rpc.course_id = c.id
    """
  end
end
