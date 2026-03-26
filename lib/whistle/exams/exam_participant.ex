defmodule Whistle.Exams.ExamParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_states ~w(waiting running paused submitted timed_out disconnected)
  @valid_license_decisions ~w(pending granted denied)

  schema "exam_participants" do
    field :exam_id, :id
    field :user_id, :id
    field :state, :string, default: "waiting"
    field :connected_at, :naive_datetime
    field :disconnected_at, :naive_datetime
    field :last_seen_at, :naive_datetime
    field :submitted_at, :naive_datetime
    field :score, :decimal
    field :max_score, :decimal
    field :passed, :boolean
    field :license_decision, :string

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def valid_states, do: @valid_states

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
      :license_decision
    ])
    |> validate_required([:exam_id, :user_id, :state])
    |> validate_inclusion(:state, @valid_states)
    |> validate_inclusion(:license_decision, @valid_license_decisions, allow_nil?: true)
    |> unique_constraint([:exam_id, :user_id])
  end
end
