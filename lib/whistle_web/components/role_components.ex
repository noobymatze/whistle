defmodule WhistleWeb.RoleComponents do
  @moduledoc """
  Role-based UI components and helpers.

  This module provides components and functions for conditionally rendering
  UI elements based on user roles and permissions.
  """

  use Phoenix.Component

  alias Whistle.Accounts.Role

  @doc """
  Renders content only if the user has the required role.

  ## Examples

      <.role_required current_user={@current_user} role="ADMIN">
        <p>This is only visible to admins</p>
      </.role_required>
      
      <.role_required current_user={@current_user} roles={["ADMIN", "CLUB_ADMIN"]}>
        <p>This is visible to admins and club admins</p>
      </.role_required>
  """
  attr :current_user, :map, required: true
  attr :role, :string, default: nil
  attr :roles, :list, default: []
  attr :role_level, :string, default: nil
  attr :admin, :boolean, default: false
  attr :full_admin, :boolean, default: false

  slot :inner_block, required: true

  def role_required(assigns) do
    if authorized?(assigns.current_user, assigns) do
      ~H"""
      {render_slot(@inner_block)}
      """
    else
      ~H""
    end
  end

  @doc """
  Renders content only if the user does NOT have the specified role.

  ## Examples

      <.role_forbidden current_user={@current_user} role="USER">
        <p>This is hidden from regular users</p>
      </.role_forbidden>
  """
  attr :current_user, :map, required: true
  attr :role, :string, default: nil
  attr :roles, :list, default: []
  attr :role_level, :string, default: nil
  attr :admin, :boolean, default: false
  attr :full_admin, :boolean, default: false

  slot :inner_block, required: true

  def role_forbidden(assigns) do
    if not authorized?(assigns.current_user, assigns) do
      ~H"""
      {render_slot(@inner_block)}
      """
    else
      ~H""
    end
  end

  @doc """
  Renders different content based on user role.

  ## Examples

      <.role_switch current_user={@current_user}>
        <:admin>
          <p>Admin content</p>
        </:admin>
        <:club_admin>
          <p>Club admin content</p>
        </:club_admin>
        <:user>
          <p>Regular user content</p>
        </:user>
      </.role_switch>
  """
  attr :current_user, :map, required: true

  slot :super_admin
  slot :admin
  slot :club_admin
  slot :instructor
  slot :user
  slot :default

  def role_switch(assigns) do
    role = assigns.current_user.role

    cond do
      role == "SUPER_ADMIN" and assigns.super_admin != [] ->
        ~H"{render_slot(@super_admin)}"

      role == "ADMIN" and assigns.admin != [] ->
        ~H"{render_slot(@admin)}"

      role == "CLUB_ADMIN" and assigns.club_admin != [] ->
        ~H"{render_slot(@club_admin)}"

      role == "INSTRUCTOR" and assigns.instructor != [] ->
        ~H"{render_slot(@instructor)}"

      role == "USER" and assigns.user != [] ->
        ~H"{render_slot(@user)}"

      assigns.default != [] ->
        ~H"{render_slot(@default)}"

      true ->
        ~H""
    end
  end

  @doc """
  Returns the role description for display.
  """
  def role_description(role) do
    Role.role_description(role)
  end

  @doc """
  Returns role options for select inputs.
  """
  def role_options do
    Role.role_options()
  end

  @doc """
  Returns assignable roles for a user.
  """
  def assignable_roles(user) do
    Role.assignable_roles(user)
    |> Enum.map(&{Role.role_description(&1), &1})
  end

  @doc """
  Checks if a user can assign a specific role.
  """
  def can_assign_role?(user, role) do
    Role.can_assign_role?(user, role)
  end

  @doc """
  Checks if a user can manage another user.
  """
  def can_manage_user?(manager, target) do
    Whistle.Accounts.can_manage_user?(manager, target)
  end

  # Private helper function for authorization checks
  defp authorized?(user, assigns) do
    cond do
      is_nil(user) ->
        false

      assigns[:role] ->
        Role.has_role?(user, assigns[:role])

      assigns[:roles] != [] ->
        user.role in assigns[:roles]

      assigns[:role_level] ->
        Role.has_role_level?(user, assigns[:role_level])

      assigns[:admin] ->
        Role.admin?(user)

      assigns[:full_admin] ->
        Role.full_admin?(user)

      true ->
        true
    end
  end
end
