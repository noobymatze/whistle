defmodule WhistleWeb.RoleComponents do
  @moduledoc """
  Components and helpers related to user roles.
  """
  use Phoenix.Component

  alias Whistle.Accounts.Role

  @doc """
  Returns assignable roles for a user, formatted for select inputs.
  """
  def assignable_roles(user) do
    user
    |> Role.assignable_roles()
    |> Enum.map(&{Role.role_description(&1), &1})
  end

  @doc """
  Returns a human-readable description of the role.
  Delegates to Role.role_description/1.
  """
  def role_description(role), do: Role.role_description(role)

  @doc """
  Checks if the current user can manage the target user.
  Delegates to Role.can_manage_user?/2.
  """
  def can_manage_user?(current_user, target_user),
    do: Role.can_manage_user?(current_user, target_user)
end
