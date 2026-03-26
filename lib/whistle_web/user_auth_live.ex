defmodule WhistleWeb.UserAuthLive do
  @moduledoc """
  LiveView on_mount hook for user authentication.

  Used via `on_mount WhistleWeb.UserAuthLive` in LiveView modules,
  which maps to the `:default` action and requires authentication.
  """

  def on_mount(:default, params, session, socket) do
    WhistleWeb.UserAuth.on_mount(:ensure_authenticated, params, session, socket)
  end
end
