defmodule Whistle.Repo.Migrations.CreateExams do
  use Ecto.Migration

  def change do
    # Questions table
    create table(:questions) do
      add :type, :string, null: false
      add :difficulty, :string, null: false
      add :body_markdown, :text, null: false
      add :explanation_markdown, :text
      add :status, :string, null: false, default: "draft"
      add :scoring_mode, :string
      add :nordref_reference, :string
      add :created_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:questions, [:difficulty])
    create index(:questions, [:status])
    create index(:questions, [:created_by])

    # Question choices
    create table(:question_choices) do
      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :body_markdown, :text, null: false
      add :position, :integer, null: false
      add :is_correct, :boolean, null: false, default: false

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:question_choices, [:question_id])

    # Question course type assignments (join table)
    create table(:question_course_types) do
      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :course_type, :string, null: false

      add :created_at, :naive_datetime, null: false
    end

    create index(:question_course_types, [:question_id])
    create unique_index(:question_course_types, [:question_id, :course_type])

    # Course type question distributions (default 50/30/20)
    create table(:course_type_question_distributions) do
      add :course_type, :string, null: false
      add :question_count, :integer, null: false, default: 20
      add :low_percentage, :integer, null: false, default: 50
      add :medium_percentage, :integer, null: false, default: 30
      add :high_percentage, :integer, null: false, default: 20
      add :pass_percentage, :integer, null: false, default: 75
      add :duration_seconds, :integer, null: false, default: 3600

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create unique_index(:course_type_question_distributions, [:course_type])

    # Exams (concrete runs)
    create table(:exams) do
      add :course_id, references(:courses, on_delete: :restrict), null: false
      add :course_type, :string, null: false
      add :title, :string, null: false
      add :state, :string, null: false, default: "waiting_room"
      add :question_count, :integer, null: false
      add :duration_seconds, :integer, null: false
      add :pass_percentage, :integer, null: false
      add :show_countdown_to_participants, :boolean, null: false, default: false
      add :started_at, :naive_datetime
      add :paused_at, :naive_datetime
      add :ended_at, :naive_datetime
      add :remaining_seconds, :integer
      add :created_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:exams, [:course_id])
    create index(:exams, [:state])
    create index(:exams, [:created_by])

    # Exam participants
    create table(:exam_participants) do
      add :exam_id, references(:exams, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :state, :string, null: false, default: "waiting"
      add :connected_at, :naive_datetime
      add :disconnected_at, :naive_datetime
      add :last_seen_at, :naive_datetime
      add :submitted_at, :naive_datetime
      add :score, :decimal
      add :max_score, :decimal
      add :passed, :boolean
      add :license_decision, :string

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:exam_participants, [:exam_id])
    create index(:exam_participants, [:user_id])
    create unique_index(:exam_participants, [:exam_id, :user_id])

    # Exam question snapshots
    create table(:exam_questions) do
      add :exam_id, references(:exams, on_delete: :delete_all), null: false
      add :source_question_id, references(:questions, on_delete: :nilify_all)
      add :position, :integer, null: false
      add :type, :string, null: false
      add :difficulty, :string, null: false
      add :body_markdown, :text, null: false
      add :explanation_markdown, :text
      add :scoring_mode, :string
      add :points, :decimal, null: false, default: 1

      add :created_at, :naive_datetime, null: false
    end

    create index(:exam_questions, [:exam_id])
    create index(:exam_questions, [:source_question_id])

    # Exam question choice snapshots
    create table(:exam_question_choices) do
      add :exam_question_id, references(:exam_questions, on_delete: :delete_all), null: false
      add :source_question_choice_id, references(:question_choices, on_delete: :nilify_all)
      add :body_markdown, :text, null: false
      add :position, :integer, null: false
      add :is_correct, :boolean, null: false, default: false

      add :created_at, :naive_datetime, null: false
    end

    create index(:exam_question_choices, [:exam_question_id])

    # Exam answers
    create table(:exam_answers) do
      add :exam_id, references(:exams, on_delete: :delete_all), null: false
      add :exam_participant_id, references(:exam_participants, on_delete: :delete_all), null: false
      add :exam_question_id, references(:exam_questions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :question_type, :string, null: false
      add :text_answer, :text
      add :is_correct, :boolean
      add :awarded_points, :decimal
      add :answered_at, :naive_datetime, null: false

      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create index(:exam_answers, [:exam_id])
    create index(:exam_answers, [:exam_participant_id])
    create index(:exam_answers, [:exam_question_id])
    create unique_index(:exam_answers, [:exam_participant_id, :exam_question_id])

    # Exam answer choices (selected choices for choice questions)
    create table(:exam_answer_choices) do
      add :exam_answer_id, references(:exam_answers, on_delete: :delete_all), null: false
      add :exam_question_choice_id,
          references(:exam_question_choices, on_delete: :delete_all),
          null: false

      add :created_at, :naive_datetime, null: false
    end

    create index(:exam_answer_choices, [:exam_answer_id])
    create unique_index(:exam_answer_choices, [:exam_answer_id, :exam_question_choice_id])
  end
end
