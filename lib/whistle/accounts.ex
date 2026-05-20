defmodule Whistle.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Whistle.Repo

  alias Whistle.Accounts.{PendingUser, Role, User, UserToken, UserView}
  alias Whistle.Oban
  alias Whistle.Workers.DeliverUserEmail

  @unconfirmed_registration_validity_in_days 3

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    email = String.trim(email)

    from(u in User,
      where: u.email == ^email,
      order_by: [desc_nulls_last: u.confirmed_at, asc: u.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a user by username.

  ## Examples

      iex> get_user_by_username("john_doe")
      %User{}

      iex> get_user_by_username("unknown")
      nil

  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: String.trim(username))
  end

  @doc """
  Gets a user by username and password.

  ## Examples

      iex> get_user_by_username_and_password("john_doe", "correct_password")
      %User{}

      iex> get_user_by_username_and_password("john_doe", "invalid_password")
      nil

  """
  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a user by username or email.

  This function tries to find the user by username first, and if not found,
  tries to find by email. Useful for password reset flows where the user
  might provide either identifier.

  ## Examples

      iex> get_user_by_username_or_email("john_doe")
      %User{}

      iex> get_user_by_username_or_email("user@example.com")
      %User{}

      iex> get_user_by_username_or_email("unknown")
      nil

  """
  def get_user_by_username_or_email(username_or_email) when is_binary(username_or_email) do
    username_or_email = String.trim(username_or_email)

    # First try to find by username
    case get_user_by_username(username_or_email) do
      nil ->
        # If not found, try to find by email
        get_user_by_email(username_or_email)

      user ->
        user
    end
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user.

  Returns `nil` if the User does not exist.
  """
  def get_user(id), do: Repo.get(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  defp unconfirmed_registration_cutoff do
    Whistle.Timezone.now_local()
    |> NaiveDateTime.add(-@unconfirmed_registration_validity_in_days, :day)
    |> NaiveDateTime.truncate(:second)
  end

  def register_pending_user(attrs, confirmation_url_fun)
      when is_map(attrs) and is_function(confirmation_url_fun, 1) do
    {encoded_token, token_hash} = PendingUser.generate_confirmation_token()
    expires_at = PendingUser.expires_at()

    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("confirmation_token_hash", token_hash)
      |> Map.put("expires_at", expires_at)

    preflight_changeset =
      PendingUser.registration_changeset(%PendingUser{}, attrs,
        hash_password: false,
        validate_username: false
      )

    if preflight_changeset.valid? do
      email = Ecto.Changeset.get_field(preflight_changeset, :email)
      username = Ecto.Changeset.get_field(preflight_changeset, :username)
      url = confirmation_url_fun.(encoded_token)

      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :expired_pending_users,
        expired_pending_users_by_identity_query(email, username)
      )
      |> Ecto.Multi.insert(:pending_user, fn _changes ->
        PendingUser.registration_changeset(%PendingUser{}, attrs)
      end)
      |> Oban.insert(
        :mail_job,
        DeliverUserEmail.new(%{
          recipient: email,
          type: "confirm",
          url: url,
          username: username
        })
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{pending_user: pending_user, mail_job: job}} ->
          {:ok, pending_user, job}

        {:error, :pending_user, changeset, _changes} ->
          {:error, changeset}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    else
      {:error, Map.put(preflight_changeset, :action, :insert)}
    end
  end

  defp expired_pending_users_by_identity_query(email, username) do
    PendingUser.expired_query()
    |> where([p], p.email == ^email or p.username == ^username)
  end

  def prune_expired_pending_users do
    {count, _} = Repo.delete_all(PendingUser.expired_query())
    {:ok, count}
  end

  def deliver_pending_user_confirmation_instructions(email, confirmation_url_fun)
      when is_binary(email) and is_function(confirmation_url_fun, 1) do
    with %PendingUser{} = pending_user <- get_latest_active_pending_user_by_email(email) do
      {encoded_token, token_hash} = PendingUser.generate_confirmation_token()
      url = confirmation_url_fun.(encoded_token)

      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :pending_user,
        PendingUser.confirmation_token_changeset(pending_user, %{
          confirmation_token_hash: token_hash,
          expires_at: PendingUser.expires_at()
        })
      )
      |> Oban.insert(
        :mail_job,
        DeliverUserEmail.new(%{
          recipient: pending_user.email,
          type: "confirm",
          url: url,
          username: pending_user.username
        })
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{mail_job: job}} -> {:ok, job}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  defp get_latest_active_pending_user_by_email(email) do
    email = PendingUser.normalize_email(email)

    PendingUser.active_query()
    |> where([p], p.email == ^email)
    |> order_by([p], desc: p.created_at, desc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  defp stringify_keys(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  @doc """
  Creates a user on behalf of an admin, applying the requested role in the
  same changeset so no partial record is ever persisted. The caller must have
  already verified that `admin` is allowed to assign the requested role before
  calling this function.
  """
  def create_user_as_admin(attrs, admin) do
    role = Map.get(attrs, "role") || Map.get(attrs, :role) || Role.default_role()

    # CLUB_ADMIN and INSTRUCTOR always create users within their own club.
    club_id =
      if admin.role in ["CLUB_ADMIN", "INSTRUCTOR"] do
        admin.club_id
      else
        attrs
        |> Map.get("club_id", Map.get(attrs, :club_id))
        |> normalize_id()
      end

    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.put_change(:role, role)
    |> Ecto.Changeset.put_change(:club_id, club_id)
    |> put_optional_change(
      :license_number,
      Map.get(attrs, "license_number") || Map.get(attrs, :license_number)
    )
    |> put_optional_change(
      :license_level,
      Map.get(attrs, "license_level") || Map.get(attrs, :license_level)
    )
    |> Repo.insert()
  end

  defp put_optional_change(changeset, field, value) do
    value =
      case value do
        value when is_binary(value) ->
          value = String.trim(value)
          if value == "", do: nil, else: value

        value ->
          value
      end

    Ecto.Changeset.put_change(changeset, field, value)
  end

  defp normalize_id(value) when is_integer(value), do: value
  defp normalize_id(nil), do: nil
  defp normalize_id(""), do: nil

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_id(_value), do: nil

  @doc """
  Updates the club for a user.

  """
  def update_club(user, club) do
    user = get_user!(user.id)

    User.club_changeset(user, %{club_id: club.id})
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs,
      hash_password: false,
      validate_email: false,
      validate_username: false
    )
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")
    url = update_email_url_fun.(encoded_token)

    enqueue_user_email(user_token, %{
      recipient: user.email,
      type: "change_email",
      url: url,
      username: user.username
    })
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  defp enqueue_user_email(user_token, args) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user_token, user_token)
    |> Oban.insert(:mail_job, DeliverUserEmail.new(args))
    |> Repo.transaction()
    |> case do
      {:ok, %{mail_job: job}} -> {:ok, job}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    cond do
      user.confirmed_at ->
        {:error, :already_confirmed}

      unconfirmed_registration_expired?(user) ->
        {:error, :registration_expired}

      true ->
        {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
        url = confirmation_url_fun.(encoded_token)

        enqueue_user_email(user_token, %{
          recipient: user.email,
          type: "confirm",
          url: url,
          username: user.username
        })
    end
  end

  defp unconfirmed_registration_expired?(%User{created_at: nil}), do: false

  defp unconfirmed_registration_expired?(%User{created_at: created_at}) do
    NaiveDateTime.compare(created_at, unconfirmed_registration_cutoff()) != :gt
  end

  @doc """
  Confirms a pending self-registration by promoting it to a user.

  Legacy user confirmation tokens are still accepted for users that were
  created before pending registrations existed.
  """
  def confirm_user(token) do
    case confirm_pending_user(token) do
      {:ok, user} -> {:ok, user}
      :error -> confirm_existing_user(token)
    end
  end

  defp confirm_pending_user(token) do
    with {:ok, token_hash} <- PendingUser.hash_confirmation_token(token),
         {:ok, %{user: user}} <- Repo.transaction(confirm_pending_user_multi(token_hash)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_pending_user_multi(token_hash) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:pending_user, fn repo, _changes ->
      pending_user =
        PendingUser
        |> where([p], p.confirmation_token_hash == ^token_hash)
        |> lock("FOR UPDATE")
        |> repo.one()

      case pending_user do
        %PendingUser{} = pending_user ->
          if PendingUser.expired?(pending_user) do
            {:error, :expired}
          else
            {:ok, pending_user}
          end

        nil ->
          {:error, :not_found}
      end
    end)
    |> Ecto.Multi.insert(:user, fn %{pending_user: pending_user} ->
      user_changeset_from_pending_user(pending_user)
    end)
    |> Ecto.Multi.delete(:delete_pending_user, fn %{pending_user: pending_user} ->
      pending_user
    end)
  end

  defp user_changeset_from_pending_user(%PendingUser{} = pending_user) do
    confirmed_at = Whistle.Timezone.now_local() |> NaiveDateTime.truncate(:second)

    %User{}
    |> Ecto.Changeset.change(%{
      email: pending_user.email,
      username: pending_user.username,
      first_name: pending_user.first_name,
      last_name: pending_user.last_name,
      mobile: pending_user.mobile,
      phone: pending_user.phone,
      birthday: pending_user.birthday,
      hashed_password: pending_user.hashed_password,
      confirmed_at: confirmed_at
    })
    |> Ecto.Changeset.unique_constraint(:username)
  end

  defp confirm_existing_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    url = reset_password_url_fun.(encoded_token)

    enqueue_user_email(user_token, %{
      recipient: user.email,
      type: "reset_password",
      url: url,
      username: user.username
    })
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def list_users() do
    UserView
    |> order_users_for_admin()
    |> Repo.all()
  end

  @doc """
  Returns a user map by id
  """
  def get_users_as_map() do
    list_users()
    |> Map.new(fn user -> {user.id, user.username} end)
  end

  ## Role management

  @doc """
  Updates a user's role.
  This should only be called by administrators.
  """
  def update_user_role(user, attrs, updated_by) when is_map(attrs) do
    role = Map.get(attrs, "role") || Map.get(attrs, :role)

    # Verify that the updater can assign this role (if role is being changed)
    if is_nil(role) or Role.can_assign_role?(updated_by, role) do
      user
      |> User.role_changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  # Backwards compatibility for when only role string is passed
  def update_user_role(user, role, updated_by) when is_binary(role) do
    update_user_role(user, %{role: role}, updated_by)
  end

  @doc """
  Updates only the user's visible license level.
  """
  def update_user_license_level(%User{} = user, license_level) do
    user
    |> User.license_level_changeset(%{license_level: license_level})
    |> Repo.update()
  end

  @doc """
  Lists users with a specific role.
  """
  def list_users_by_role(role) do
    from(u in User, where: u.role == ^role)
    |> Repo.all()
  end

  @doc """
  Lists users that can be managed by the given user.
  """
  def list_manageable_users(manager) do
    case manager.role do
      "SUPER_ADMIN" ->
        from(u in UserView, where: u.role != "SUPER_ADMIN")
        |> order_users_for_admin()
        |> Repo.all()

      "ADMIN" ->
        from(u in UserView, where: u.role not in ["SUPER_ADMIN", "ADMIN"])
        |> order_users_for_admin()
        |> Repo.all()

      "CLUB_ADMIN" ->
        from(u in UserView,
          where: u.club_id == ^manager.club_id and u.role in ["INSTRUCTOR", "USER"]
        )
        |> order_users_for_admin()
        |> Repo.all()

      "INSTRUCTOR" ->
        from(u in UserView,
          where: u.club_id == ^manager.club_id and u.role == "USER"
        )
        |> order_users_for_admin()
        |> Repo.all()

      _ ->
        []
    end
  end

  defp order_users_for_admin(query) do
    from(u in query,
      order_by: [
        asc_nulls_last: u.club_name,
        asc_nulls_last: u.first_name,
        asc_nulls_last: u.last_name,
        asc: u.username
      ]
    )
  end

  @doc """
  Deletes a user account and all associated tokens.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Checks if a user can manage another user.
  """
  def can_manage_user?(manager, target) do
    # Allow self-management for admin roles
    if manager.id == target.id and Role.admin?(manager) do
      true
    else
      # Basic role hierarchy check
      can_manage_by_role = Role.can_manage_user?(manager, target)

      # Club-specific restrictions
      case manager.role do
        role when role in ["SUPER_ADMIN", "ADMIN"] ->
          # Super admin and admin can manage anyone (subject to role hierarchy)
          can_manage_by_role

        role when role in ["CLUB_ADMIN", "INSTRUCTOR"] ->
          # Club-scoped roles can only manage users in their own club
          can_manage_by_role and manager.club_id == target.club_id

        _ ->
          false
      end
    end
  end

  @doc """
  Returns a changeset for changing a user's role.
  """
  def change_user_role(user, attrs \\ %{}) do
    User.role_changeset(user, attrs)
  end
end
