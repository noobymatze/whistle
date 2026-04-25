defmodule Whistle.Repo.Migrations.AddExamVariants do
  use Ecto.Migration

  def change do
    create table(:exam_variants) do
      add :name, :string, null: false
      add :course_type, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :duration_seconds, :integer, null: false
      add :l1_threshold, :integer
      add :l2_threshold, :integer
      add :l3_threshold, :integer
      add :pass_threshold, :integer

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create unique_index(:exam_variants, [:name, :course_type])
    create index(:exam_variants, [:course_type, :status])

    create constraint(:exam_variants, :exam_variants_course_type_check,
             check: "course_type IN ('F', 'J', 'G')"
           )

    create constraint(:exam_variants, :exam_variants_status_check,
             check: "status IN ('draft', 'enabled', 'disabled')"
           )

    create table(:exam_variant_questions) do
      add :exam_variant_id, references(:exam_variants, on_delete: :delete_all), null: false
      add :question_id, references(:questions, on_delete: :restrict), null: false
      add :position, :integer, null: false

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create unique_index(:exam_variant_questions, [:exam_variant_id, :question_id])
    create unique_index(:exam_variant_questions, [:exam_variant_id, :position])
    create index(:exam_variant_questions, [:question_id])

    alter table(:exams) do
      add :exam_variant_id, references(:exam_variants, on_delete: :restrict)
    end

    create index(:exams, [:exam_variant_id])
  end
end
