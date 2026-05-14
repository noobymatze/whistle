defmodule Whistle.Workers.PruneUnconfirmedUsers do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Oban.Job
  alias Whistle.Accounts

  @impl Oban.Worker
  def perform(%Job{}) do
    case Accounts.prune_expired_unconfirmed_users() do
      {:ok, count} ->
        Logger.info("Pruned #{count} expired unconfirmed users")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
