defmodule WhistleWeb.ControllerHelpers do
  @moduledoc """
  Helpers shared across controllers.
  """

  import Phoenix.Controller
  import Plug.Conn

  def parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  def parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  def parse_id(_), do: :error

  def render_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: WhistleWeb.ErrorHTML)
    |> render(:"404")
    |> halt()
  end
end
