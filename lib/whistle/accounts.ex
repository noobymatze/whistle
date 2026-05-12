defmodule Whistle.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Whistle.Repo

  alias Whistle.Accounts.{Role, User, UserInvitation, UserToken, UserView}
  alias Whistle.Clubs.Club
  alias Whistle.Oban
  alias Whistle.Workers.DeliverUserEmail

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

  def register_user_with_invitation(attrs, invite_code) when is_map(attrs) do
    email =
      attrs |> Map.get("email", Map.get(attrs, :email, "")) |> UserInvitation.normalize_email()

    Repo.transaction(fn ->
      with %UserInvitation{} = invitation <- get_usable_invitation_for_update(email, invite_code) do
        changeset =
          %User{}
          |> User.registration_changeset(attrs)
          |> Ecto.Changeset.put_change(:club_id, invitation.club_id)

        case Repo.insert(changeset) do
          {:ok, user} ->
            invitation
            |> UserInvitation.accept_changeset()
            |> Repo.update!()

            user

          {:error, changeset} ->
            Repo.rollback({:error, changeset})
        end
      else
        _ ->
          changeset =
            %User{}
            |> change_user_registration(attrs)
            |> Map.put(:action, :insert)

          Repo.rollback({:error, :invalid_invitation, changeset})
      end
    end)
    |> case do
      {:ok, %User{} = user} ->
        {:ok, user}

      {:error, {:error, :invalid_invitation, changeset}} ->
        {:error, :invalid_invitation, changeset}

      {:error, {:error, changeset}} ->
        {:error, changeset}
    end
  end

  def change_user_invitation(%UserInvitation{} = invitation, attrs \\ %{}) do
    UserInvitation.create_changeset(invitation, attrs)
  end

  def invite_user(%User{} = inviter, attrs, invitation_url_fun)
      when is_function(invitation_url_fun, 2) do
    if Role.can_access_user_admin?(inviter) do
      do_invite_user(inviter, attrs, invitation_url_fun)
    else
      {:error, :unauthorized}
    end
  end

  defp do_invite_user(inviter, attrs, invitation_url_fun) do
    {code, code_hash} = UserInvitation.generate_code()

    email =
      attrs |> Map.get("email", Map.get(attrs, :email, "")) |> UserInvitation.normalize_email()

    club_id = invite_club_id(inviter, attrs)

    invitation_attrs = %{
      email: email,
      club_id: club_id,
      invited_by_user_id: inviter.id,
      expires_at: UserInvitation.expires_at(),
      code_hash: code_hash
    }

    changeset = UserInvitation.create_changeset(%UserInvitation{}, invitation_attrs)
    club = if club_id, do: Repo.get(Club, club_id), else: nil
    invitation = struct(UserInvitation, Map.put(invitation_attrs, :club, club))
    url = invitation_url_fun.(invitation, code)

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :revoke_existing,
      pending_invitations_by_email_query(email),
      set: [revoked_at: Whistle.Timezone.now_local() |> NaiveDateTime.truncate(:second)]
    )
    |> Ecto.Multi.insert(:invitation, changeset)
    |> Oban.insert(
      :mail_job,
      DeliverUserEmail.new(%{
        recipient: email,
        type: "invitation",
        url: url,
        invite_code: code,
        username: email,
        inviter_name: user_display_name(inviter),
        club_name: club && club.name
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{invitation: invitation, mail_job: job}} -> {:ok, invitation, job}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp get_usable_invitation_for_update(email, invite_code)
       when is_binary(email) and is_binary(invite_code) do
    code_hash = UserInvitation.hash_code(invite_code)

    Repo.one(
      from i in UserInvitation,
        where:
          i.email == ^email and i.code_hash == ^code_hash and is_nil(i.accepted_at) and
            is_nil(i.revoked_at),
        lock: "FOR UPDATE"
    )
    |> case do
      %UserInvitation{} = invitation ->
        if UserInvitation.usable?(invitation), do: invitation, else: nil

      nil ->
        nil
    end
  end

  defp get_usable_invitation_for_update(_email, _invite_code), do: nil

  defp pending_invitations_by_email_query(email) do
    from i in UserInvitation,
      where: i.email == ^email and is_nil(i.accepted_at) and is_nil(i.revoked_at)
  end

  defp invite_club_id(%User{role: role, club_id: club_id}, _attrs)
       when role in ["CLUB_ADMIN", "INSTRUCTOR"],
       do: club_id

  defp invite_club_id(_inviter, attrs) do
    attrs
    |> Map.get("club_id", Map.get(attrs, :club_id))
    |> normalize_id()
  end

  defp user_display_name(%User{} = user) do
    [user.first_name, user.last_name]
    |> Enum.filter(&(&1 && String.trim(&1) != ""))
    |> case do
      [] -> user.username || user.email
      names -> Enum.join(names, " ")
    end
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
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
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

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
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
