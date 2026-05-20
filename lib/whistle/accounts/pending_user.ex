defmodule Whistle.Accounts.PendingUser do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Whistle.Accounts.{PendingUser, User}
  alias Whistle.Repo
  alias Whistle.Timezone

  @hash_algorithm :sha256
  @rand_size 32
  @validity_in_days 3

  schema "pending_users" do
    field :email, :string
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :first_name, :string
    field :last_name, :string
    field :mobile, :string
    field :phone, :string
    field :birthday, :date
    field :confirmation_token_hash, :binary, redact: true
    field :expires_at, :naive_datetime

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def registration_changeset(pending_user, attrs, opts \\ []) do
    pending_user
    |> cast(attrs, [
      :email,
      :username,
      :password,
      :first_name,
      :last_name,
      :mobile,
      :phone,
      :birthday,
      :confirmation_token_hash,
      :expires_at
    ])
    |> validate_required([
      :email,
      :username,
      :password,
      :first_name,
      :last_name,
      :birthday,
      :confirmation_token_hash,
      :expires_at
    ])
    |> validate_email()
    |> validate_username(opts)
    |> validate_birthday()
    |> validate_password(opts)
    |> unique_constraint(:confirmation_token_hash)
  end

  def confirmation_token_changeset(%PendingUser{} = pending_user, attrs) do
    pending_user
    |> cast(attrs, [:confirmation_token_hash, :expires_at])
    |> validate_required([:confirmation_token_hash, :expires_at])
    |> unique_constraint(:confirmation_token_hash)
  end

  def generate_confirmation_token do
    token = :crypto.strong_rand_bytes(@rand_size)
    {Base.url_encode64(token, padding: false), hash_token(token)}
  end

  def hash_confirmation_token(encoded_token) when is_binary(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, decoded_token} -> {:ok, hash_token(decoded_token)}
      :error -> :error
    end
  end

  def expires_at do
    now()
    |> NaiveDateTime.add(@validity_in_days, :day)
    |> NaiveDateTime.truncate(:second)
  end

  def expired?(%PendingUser{expires_at: expires_at}) do
    NaiveDateTime.compare(expires_at, now()) != :gt
  end

  def active_query do
    now = now()
    from p in PendingUser, where: p.expires_at > ^now
  end

  def expired_query do
    now = now()
    from p in PendingUser, where: p.expires_at <= ^now
  end

  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  def normalize_email(email), do: email

  defp hash_token(token), do: :crypto.hash(@hash_algorithm, token)

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
  end

  defp validate_username(changeset, opts) do
    changeset
    |> update_change(:username, &normalize_username/1)
    |> validate_length(:username, min: 3, max: 20)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_.]+$/,
      message: "must contain only letters, numbers, dots, and underscores"
    )
    |> maybe_validate_unique_username(opts)
  end

  defp normalize_username(username) when is_binary(username), do: String.trim(username)
  defp normalize_username(username), do: username

  defp maybe_validate_unique_username(changeset, opts) do
    if Keyword.get(opts, :validate_username, true) do
      changeset
      |> unsafe_validate_unique(:username, Repo)
      |> validate_username_not_registered()
      |> unique_constraint(:username)
    else
      changeset
    end
  end

  defp validate_username_not_registered(changeset) do
    username = get_field(changeset, :username)

    if is_binary(username) and Repo.exists?(from u in User, where: u.username == ^username) do
      add_error(changeset, :username, "has already been taken")
    else
      changeset
    end
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp validate_birthday(changeset) do
    case get_field(changeset, :birthday) do
      %Date{} = birthday ->
        today = Timezone.today_local()
        minimum_birthday = minimum_birthday(today)

        cond do
          Date.compare(birthday, today) == :gt ->
            add_error(changeset, :birthday, "darf nicht in der Zukunft liegen")

          Date.compare(birthday, minimum_birthday) == :gt ->
            add_error(changeset, :birthday, "muss mindestens 7 Jahre zurückliegen")

          true ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp minimum_birthday(%Date{} = today) do
    target_year = today.year - 7
    days_in_month = Date.days_in_month(Date.new!(target_year, today.month, 1))

    Date.new!(target_year, today.month, min(today.day, days_in_month))
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp now do
    Timezone.now_local() |> NaiveDateTime.truncate(:second)
  end
end
