defmodule WhistleWeb.UserAuthLive do
  use Phoenix.VerifiedRoutes,
    endpoint: WhistleWeb.Endpoint,
    router: WhistleWeb.Router

  import Phoenix.Component
  import Phoenix.LiveView

  # from `mix phx.gen.auth`
  alias Whistle.Accounts

  @spec on_mount(:default, any(), map(), map()) ::
          {:cont, %{:assigns => atom() | map(), optional(any()) => any()}}
          | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, %{"user_token" => user_token} = _session, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/users/log_in")}
    end
  end
end
