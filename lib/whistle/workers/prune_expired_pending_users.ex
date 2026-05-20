defmodule Whistle.Workers.PruneExpiredPendingUsers do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Oban.Job
  alias Whistle.Accounts

  @impl Oban.Worker
  def perform(%Job{}) do
    {:ok, count} = Accounts.prune_expired_pending_users()
    Logger.info("Pruned #{count} expired pending users")
    :ok
  end
end
