defmodule Whistle.TestSupport.FailingSwooshAdapter do
  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, :smtp_unavailable}
end
