defmodule Whistle.AccountsTest do
  use Whistle.DataCase

  alias Whistle.Accounts

  import Whistle.AccountsFixtures
  alias Whistle.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user_by_username/1" do
    test "does not return the user if the username does not exist" do
      refute Accounts.get_user_by_username("unknown_user")
    end

    test "returns the user if the username exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_username(user.username)
    end
  end

  describe "get_user_by_username_and_password/2" do
    test "does not return the user if the username does not exist" do
      refute Accounts.get_user_by_username_and_password("unknown_user", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_username_and_password(user.username, "invalid")
    end

    test "returns the user if the username and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_username_and_password(user.username, valid_user_password())
    end
  end

  describe "get_user_by_username_or_email/1" do
    test "returns the user when username is provided" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_username_or_email(user.username)
    end

    test "returns the user when email is provided" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_username_or_email(user.email)
    end

    test "returns nil when neither username nor email exists" do
      refute Accounts.get_user_by_username_or_email("unknown")
    end

    test "prioritizes username over email when searching" do
      # Create two users with distinct usernames
      user1 = user_fixture(%{email: "shared@example.com", username: "user_one"})
      user2 = user_fixture(%{email: "other@example.com", username: "user_two"})

      # Search by username should find the correct user
      result1 = Accounts.get_user_by_username_or_email("user_one")
      assert result1.id == user1.id

      result2 = Accounts.get_user_by_username_or_email("user_two")
      assert result2.id == user2.id

      # Search by email should find the correct user
      result3 = Accounts.get_user_by_username_or_email("other@example.com")
      assert result3.id == user2.id
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates username uniqueness" do
      %{username: username} = user_fixture()

      {:error, changeset} =
        Accounts.register_user(%{
          username: username,
          email: unique_user_email(),
          password: valid_user_password()
        })

      assert "has already been taken" in errors_on(changeset).username
    end

    test "allows multiple users with the same email but different usernames" do
      shared_email = unique_user_email()

      # Create first user with email
      {:ok, user1} =
        Accounts.register_user(%{
          email: shared_email,
          username: unique_username(),
          password: valid_user_password(),
          first_name: "Test",
          last_name: "User",
          birthday: ~D[1990-01-01]
        })

      # Create second user with same email but different username
      {:ok, user2} =
        Accounts.register_user(%{
          email: shared_email,
          username: unique_username(),
          password: valid_user_password(),
          first_name: "Test",
          last_name: "User",
          birthday: ~D[1990-01-01]
        })

      assert user1.email == user2.email
      assert user1.username != user2.username
      assert user1.id != user2.id
    end

    test "registers users with a hashed password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration(%User{})
      assert changeset.required == [:password, :username, :email, :first_name, :last_name, :birthday]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          %User{},
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture()}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} = Accounts.apply_user_email(user, valid_user_password(), %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "allows changing email to one already in use (email no longer unique)", %{user: user} do
      %{email: email} = user_fixture()
      password = valid_user_password()

      # Email uniqueness is no longer enforced, so this should succeed
      {:ok, _applied_user} = Accounts.apply_user_email(user, password, %{email: email})
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()
      {:ok, user} = Accounts.apply_user_email(user, valid_user_password(), %{email: email})
      assert user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert Accounts.update_user_email(user, token) == :ok
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      assert changed_user.confirmed_at
      assert changed_user.confirmed_at != user.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{password: valid_user_password()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_user_password(user, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new valid password"})
      assert is_nil(updated_user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "role management" do
    setup do
      # Create a club first for consistent club_id
      club = Whistle.ClubsFixtures.club_fixture()

      %{
        super_admin: user_fixture(%{role: "SUPER_ADMIN"}),
        admin: user_fixture(%{role: "ADMIN"}),
        club_admin: user_fixture(%{role: "CLUB_ADMIN", club_id: club.id}),
        instructor: user_fixture(%{role: "INSTRUCTOR", club_id: club.id}),
        user: user_fixture(%{role: "USER", club_id: club.id})
      }
    end

    test "register_user creates user with default role" do
      {:ok, user} = Accounts.register_user(valid_user_attributes())
      assert user.role == "USER"
    end

    test "register_user validates role when provided" do
      {:error, changeset} = Accounts.register_user(valid_user_attributes(%{role: "INVALID_ROLE"}))

      assert "must be one of: SUPER_ADMIN, ADMIN, CLUB_ADMIN, INSTRUCTOR, USER" in errors_on(
               changeset
             ).role
    end

    test "register_user accepts valid roles" do
      {:ok, user} = Accounts.register_user(valid_user_attributes(%{role: "ADMIN"}))
      assert user.role == "ADMIN"
    end

    test "super admin can assign any role", %{super_admin: super_admin, user: user} do
      {:ok, updated_user} = Accounts.update_user_role(user, "ADMIN", super_admin)
      assert updated_user.role == "ADMIN"
    end

    test "admin can assign roles except super admin", %{admin: admin, user: user} do
      {:ok, updated_user} = Accounts.update_user_role(user, "CLUB_ADMIN", admin)
      assert updated_user.role == "CLUB_ADMIN"

      assert {:error, :unauthorized} = Accounts.update_user_role(user, "SUPER_ADMIN", admin)
    end

    test "club admin can assign limited roles", %{club_admin: club_admin, user: user} do
      {:ok, updated_user} = Accounts.update_user_role(user, "INSTRUCTOR", club_admin)
      assert updated_user.role == "INSTRUCTOR"

      assert {:error, :unauthorized} = Accounts.update_user_role(user, "ADMIN", club_admin)
    end

    test "instructor cannot assign roles", %{instructor: instructor, user: user} do
      assert {:error, :unauthorized} = Accounts.update_user_role(user, "USER", instructor)
    end

    test "validates role value in update_user_role", %{super_admin: super_admin, user: user} do
      {:error, changeset} = Accounts.update_user_role(user, "INVALID", super_admin)

      assert "must be one of: SUPER_ADMIN, ADMIN, CLUB_ADMIN, INSTRUCTOR, USER" in errors_on(
               changeset
             ).role
    end

    test "list_users_by_role returns users with specific role", %{
      admin: admin,
      club_admin: club_admin
    } do
      admins = Accounts.list_users_by_role("ADMIN")
      admin_ids = Enum.map(admins, & &1.id)

      assert admin.id in admin_ids
      refute club_admin.id in admin_ids
    end

    test "super admin can manage all except other super admins", %{
      super_admin: super_admin,
      admin: admin,
      user: user
    } do
      manageable = Accounts.list_manageable_users(super_admin)
      manageable_ids = Enum.map(manageable, & &1.id)

      assert admin.id in manageable_ids
      assert user.id in manageable_ids
      refute super_admin.id in manageable_ids
    end

    test "admin can manage all except super admins and other admins", %{
      admin: admin,
      club_admin: club_admin,
      user: user,
      super_admin: super_admin
    } do
      manageable = Accounts.list_manageable_users(admin)
      manageable_ids = Enum.map(manageable, & &1.id)

      assert club_admin.id in manageable_ids
      assert user.id in manageable_ids
      refute super_admin.id in manageable_ids
      refute admin.id in manageable_ids
    end

    test "club admin can manage users in their club with lower roles", %{
      club_admin: club_admin,
      instructor: instructor,
      user: user
    } do
      manageable = Accounts.list_manageable_users(club_admin)
      manageable_ids = Enum.map(manageable, & &1.id)

      assert instructor.id in manageable_ids
      assert user.id in manageable_ids
      refute club_admin.id in manageable_ids
    end

    test "instructor cannot manage any users", %{instructor: instructor} do
      manageable = Accounts.list_manageable_users(instructor)
      assert manageable == []
    end

    test "can_manage_user returns true when manager can manage target", %{
      admin: admin,
      user: user
    } do
      assert Accounts.can_manage_user?(admin, user)
    end

    test "can_manage_user returns false when manager cannot manage target", %{user: user1} do
      user2 = user_fixture(%{role: "USER"})
      refute Accounts.can_manage_user?(user1, user2)
    end

    test "club admin can only manage users in same club", %{club_admin: club_admin, user: user} do
      # Same club
      assert Accounts.can_manage_user?(club_admin, user)

      # Different club - create another club
      different_club = Whistle.ClubsFixtures.club_fixture()
      different_club_user = user_fixture(%{role: "USER", club_id: different_club.id})
      refute Accounts.can_manage_user?(club_admin, different_club_user)
    end

    test "change_user_role returns a changeset for role changes", %{user: user} do
      changeset = Accounts.change_user_role(user, %{role: "INSTRUCTOR"})
      assert %Ecto.Changeset{} = changeset
      assert get_change(changeset, :role) == "INSTRUCTOR"
    end
  end
end
