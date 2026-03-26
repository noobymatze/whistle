defmodule Whistle.Repo.Migrations.AddSelectableCoursesView do
  use Ecto.Migration

  def up do
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

  def down do
    execute "DROP VIEW IF EXISTS courses_view"
  end
end
