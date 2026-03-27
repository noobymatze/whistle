defmodule Whistle.Exams.ExamParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_states ~w(waiting running paused submitted timed_out disconnected)
  @valid_license_decisions ~w(pending granted denied)
  @valid_exam_outcomes ~w(l3_pass l2_pass l1_eligible fail not_applicable)

  schema "exam_participants" do
    field :exam_id, :id
    field :user_id, :id
    field :state, :string, default: "waiting"
    field :connected_at, :naive_datetime
    field :disconnected_at, :naive_datetime
    field :last_seen_at, :naive_datetime
    field :submitted_at, :naive_datetime

    # Legacy fields (kept for compatibility)
    field :score, :decimal
    field :max_score, :decimal
    field :passed, :boolean
    field :license_decision, :string

    # New structured outcome fields
    field :achieved_points, :integer
    field :max_points, :integer
    field :exam_outcome, :string

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def valid_states, do: @valid_states
  def valid_exam_outcomes, do: @valid_exam_outcomes

  @doc false
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [
      :exam_id,
      :user_id,
      :state,
      :connected_at,
      :disconnected_at,
      :last_seen_at,
      :submitted_at,
      :score,
      :max_score,
      :passed,
      :license_decision,
      :achieved_points,
      :max_points,
      :exam_outcome
    ])
    |> validate_required([:exam_id, :user_id, :state])
    |> validate_inclusion(:state, @valid_states)
    |> validate_inclusion(:license_decision, @valid_license_decisions, allow_nil?: true)
    |> validate_inclusion(:exam_outcome, @valid_exam_outcomes, allow_nil?: true)
    |> unique_constraint([:exam_id, :user_id])
  end
end
