defmodule Whistle.Repo.Migrations.AddMaxParticipantsToCourseDates do
  use Ecto.Migration

  def change do
    alter table(:course_dates) do
      add :max_participants, :integer
    end

    create constraint(:course_dates, :course_dates_max_participants_positive,
             check: "max_participants IS NULL OR max_participants > 0"
           )
  end
end
