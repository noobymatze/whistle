defmodule Whistle.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WhistleWeb.Telemetry,
      Whistle.Repo,
      {DNSCluster, query: Application.get_env(:whistle, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Whistle.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Whistle.Finch},
      # Start a worker by calling: Whistle.Worker.start_link(arg)
      # {Whistle.Worker, arg},
      # Start to serve requests, typically the last entry
      WhistleWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Whistle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhistleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
