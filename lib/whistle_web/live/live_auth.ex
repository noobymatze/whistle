defmodule WhistleWeb.LiveAuth do
  @moduledoc """
  Authorization helpers for LiveView.

  This module provides functions for checking user authorization in LiveView contexts.
  It should be used in LiveView mount callbacks to ensure users have proper permissions.
  """

  import Phoenix.LiveView

  alias Whistle.Accounts.Role

  @doc """
  Requires a user to have a specific role.

  ## Usage

      def mount(_params, _session, socket) do
        socket = assign_current_user(socket, session)
        
        if authorized?(socket, role: "ADMIN") do
          {:ok, socket}
        else
          {:ok, redirect(socket, to: "/")}
        end
      end
  """
  def authorized?(socket, opts) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        false

      opts[:role] ->
        Role.has_role?(user, opts[:role])

      opts[:role_level] ->
        Role.has_role_level?(user, opts[:role_level])

      opts[:roles] ->
        user.role in opts[:roles]

      opts[:admin] ->
        Role.admin?(user)

      opts[:full_admin] ->
        Role.full_admin?(user)

      true ->
        true
    end
  end

  @doc """
  Requires authentication and authorization, redirecting if not authorized.

  ## Usage

      def mount(_params, _session, socket) do
        socket = assign_current_user(socket, session)
        
        case require_auth(socket, role: "ADMIN") do
          {:ok, socket} -> {:ok, socket}
          {:error, socket} -> {:ok, socket}
        end
      end
  """
  def require_auth(socket, opts \\ []) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        socket =
          socket
          |> put_flash(:error, "Du musst angemeldet sein, um auf diese Seite zuzugreifen.")
          |> redirect(to: "/users/log_in")

        {:error, socket}

      authorized?(socket, opts) ->
        {:ok, socket}

      true ->
        socket =
          socket
          |> put_flash(:error, "Du hast keine Berechtigung, auf diese Seite zuzugreifen.")
          |> redirect(to: "/")

        {:error, socket}
    end
  end

  @doc """
  Macro for use in LiveView modules to add authorization checks.

  ## Usage

      defmodule MyLiveView do
        use WhistleWeb.LiveAuth
        
        def mount(_params, _session, socket) do
          socket = assign_current_user(socket, session)
          
          with {:ok, socket} <- require_role(socket, :admin) do
            {:ok, socket}
          end
        end
      end
  """
  defmacro __using__(_) do
    quote do
      import WhistleWeb.LiveAuth

      def require_role(socket, role) when is_atom(role) do
        require_auth(socket, role: Atom.to_string(role) |> String.upcase())
      end

      def require_role(socket, role) when is_binary(role) do
        require_auth(socket, role: role)
      end

      def require_admin(socket) do
        require_auth(socket, admin: true)
      end

      def require_full_admin(socket) do
        require_auth(socket, full_admin: true)
      end
    end
  end
end
