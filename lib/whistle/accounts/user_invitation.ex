defmodule Whistle.Accounts.UserInvitation do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Whistle.Accounts.User
  alias Whistle.Accounts.UserInvitation
  alias Whistle.Clubs.Club
  alias Whistle.Repo
  alias Whistle.Timezone

  @hash_algorithm :sha256
  @rand_size 18
  @validity_in_days 14

  schema "user_invitations" do
    field :email, :string
    field :code_hash, :binary, redact: true
    field :expires_at, :naive_datetime
    field :accepted_at, :naive_datetime
    field :revoked_at, :naive_datetime

    belongs_to :invited_by_user, User
    belongs_to :club, Club

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def create_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :club_id, :invited_by_user_id, :expires_at, :code_hash])
    |> validate_required([:email, :code_hash, :invited_by_user_id, :expires_at])
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> validate_email_not_registered()
    |> foreign_key_constraint(:invited_by_user_id)
    |> foreign_key_constraint(:club_id)
    |> unique_constraint(:code_hash)
  end

  def accept_changeset(%UserInvitation{} = invitation) do
    change(invitation, accepted_at: now())
  end

  def expired?(%UserInvitation{expires_at: expires_at}) do
    NaiveDateTime.compare(expires_at, now()) != :gt
  end

  def usable?(%UserInvitation{} = invitation) do
    is_nil(invitation.accepted_at) and is_nil(invitation.revoked_at) and not expired?(invitation)
  end

  def generate_code do
    code = :crypto.strong_rand_bytes(@rand_size) |> Base.url_encode64(padding: false)
    {code, hash_code(code)}
  end

  def hash_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> Base.url_decode64(padding: false)
    |> case do
      {:ok, decoded_code} -> :crypto.hash(@hash_algorithm, decoded_code)
      :error -> :crypto.hash(@hash_algorithm, String.trim(code))
    end
  end

  def expires_at do
    now()
    |> NaiveDateTime.add(@validity_in_days, :day)
    |> NaiveDateTime.truncate(:second)
  end

  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  def normalize_email(email), do: email

  defp validate_email_not_registered(changeset) do
    email = get_field(changeset, :email)

    if is_binary(email) and Repo.exists?(from u in User, where: u.email == ^email) do
      add_error(changeset, :email, "ist bereits registriert")
    else
      changeset
    end
  end

  defp now do
    Timezone.now_local() |> NaiveDateTime.truncate(:second)
  end
end
