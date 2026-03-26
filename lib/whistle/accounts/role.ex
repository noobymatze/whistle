defmodule Whistle.Accounts.Role do
  @moduledoc """
  Role management and authorization logic.

  This module centralizes all role-related logic and provides a single
  source of truth for role definitions and permissions.

  Based on the Wicket implementation with 5-tier role system:
  - SUPER_ADMIN: Full system access
  - ADMIN: Can manage all except SUPER_ADMIN
  - CLUB_ADMIN: Can manage club users and instructors
  - INSTRUCTOR: Limited permissions
  - USER: Basic access
  """

  @roles ~w(SUPER_ADMIN ADMIN CLUB_ADMIN INSTRUCTOR USER)
  @default_role "USER"

  @doc """
  Returns all available roles.
  """
  def roles, do: @roles

  @doc """
  Returns the default role for new users.
  """
  def default_role, do: @default_role

  @doc """
  Validates that a role is valid.
  """
  def valid_role?(role) when role in @roles, do: true
  def valid_role?(_), do: false

  @doc """
  Returns the role hierarchy level (lower number = higher permission).
  """
  def role_level("SUPER_ADMIN"), do: 0
  def role_level("ADMIN"), do: 1
  def role_level("CLUB_ADMIN"), do: 2
  def role_level("INSTRUCTOR"), do: 3
  def role_level("USER"), do: 4
  def role_level(_), do: 99

  @doc """
  Checks if a user has a specific role.
  """
  def has_role?(%{role: role}, required_role) do
    role == required_role
  end

  @doc """
  Checks if a user has at least the required role level.
  A user with a higher role (lower level number) can access
  resources requiring a lower role.
  """
  def has_role_level?(%{role: user_role}, required_role) do
    role_level(user_role) <= role_level(required_role)
  end

  @doc """
  Checks if a user can manage another user based on role hierarchy.
  """
  def can_manage_user?(%{role: manager_role}, %{role: target_role}) do
    manager_level = role_level(manager_role)
    target_level = role_level(target_role)

    # Can manage users with lower role level (higher number)
    # SUPER_ADMIN can manage everyone except other SUPER_ADMINs
    # ADMIN can manage users below them, except SUPER_ADMIN and other ADMINs
    # Others can only manage lower levels
    can_manage_by_level =
      case manager_role do
        # Can manage anyone except other SUPER_ADMINs
        "SUPER_ADMIN" -> manager_level < target_level
        # Can manage anyone except SUPER_ADMIN and other ADMINs
        "ADMIN" -> manager_level < target_level
        # Others can only manage lower levels
        _ -> manager_level < target_level
      end

    can_manage_roles?(manager_role) and can_manage_by_level
  end

  # Helper function to determine if a role can manage other users
  defp can_manage_roles?(role) do
    role in ["SUPER_ADMIN", "ADMIN", "CLUB_ADMIN"]
  end

  @doc """
  Checks if a user can assign a specific role.
  """
  def can_assign_role?(%{role: user_role}, target_role) do
    case user_role do
      "SUPER_ADMIN" ->
        # SUPER_ADMIN can assign any role
        true

      "ADMIN" ->
        # ADMIN can assign all roles except SUPER_ADMIN
        target_role != "SUPER_ADMIN"

      "CLUB_ADMIN" ->
        # CLUB_ADMIN can only assign CLUB_ADMIN, INSTRUCTOR, and USER
        target_role in ["CLUB_ADMIN", "INSTRUCTOR", "USER"]

      _ ->
        # INSTRUCTOR and USER cannot assign roles
        false
    end
  end

  @doc """
  Returns the roles that a user can assign to others.
  """
  def assignable_roles(%{role: user_role}) do
    case user_role do
      "SUPER_ADMIN" -> @roles
      "ADMIN" -> @roles -- ["SUPER_ADMIN"]
      "CLUB_ADMIN" -> ["CLUB_ADMIN", "INSTRUCTOR", "USER"]
      _ -> []
    end
  end

  @doc """
  Checks if a user has admin privileges (SUPER_ADMIN, ADMIN, or CLUB_ADMIN).
  """
  def admin?(%{role: role}) do
    role in ["SUPER_ADMIN", "ADMIN", "CLUB_ADMIN"]
  end

  @doc """
  Checks if a user has super admin privileges.
  """
  def super_admin?(%{role: "SUPER_ADMIN"}), do: true
  def super_admin?(_), do: false

  @doc """
  Checks if a user has full admin privileges (SUPER_ADMIN or ADMIN).
  """
  def full_admin?(%{role: role}) do
    role in ["SUPER_ADMIN", "ADMIN"]
  end

  @doc """
  Checks if a user can access admin features.
  """
  def can_access_admin?(%{role: role}) do
    role in ["SUPER_ADMIN", "ADMIN", "CLUB_ADMIN"]
  end

  @doc """
  Checks if a user can manage courses.
  """
  def can_manage_courses?(%{role: role}) do
    role in ["SUPER_ADMIN", "ADMIN", "CLUB_ADMIN", "INSTRUCTOR"]
  end

  @doc """
  Checks if a user can view all users.
  """
  def can_view_all_users?(%{role: role}) do
    role in ["SUPER_ADMIN", "ADMIN"]
  end

  @doc """
  Checks if a user can manage club users (users in their club).
  """
  def can_manage_club_users?(%{role: role}) do
    role in ["SUPER_ADMIN", "ADMIN", "CLUB_ADMIN"]
  end

  @doc """
  Returns a human-readable description of the role.
  """
  def role_description("SUPER_ADMIN"), do: "Super Administrator"
  def role_description("ADMIN"), do: "Administrator"
  def role_description("CLUB_ADMIN"), do: "Club Administrator"
  def role_description("INSTRUCTOR"), do: "Instructor"
  def role_description("USER"), do: "User"
  def role_description(_), do: "Unknown"

  @doc """
  Returns role options for forms, with description.
  """
  def role_options do
    @roles
    |> Enum.map(&{role_description(&1), &1})
  end
end
