defmodule Whistle.Workers.DeliverAnnouncement do
  @moduledoc """
  Drains the announcement broadcast queued by the now-removed admin
  announcement feature. Kept around only to process leftover jobs in the
  database; can be deleted once `oban_jobs` has no rows referencing it.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 5

  alias Oban.Job
  alias Whistle.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Job{
        args: %{
          "recipient" => recipient,
          "username" => username,
          "subject" => subject,
          "body" => body
        }
      }) do
    user = %{email: recipient, username: username}

    case UserNotifier.deliver_announcement(user, subject, body) do
      {:ok, _email} ->
        Process.sleep(1_000)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def perform(%Job{}), do: {:discard, "invalid args"}
end
