defmodule Whistle.Workers.DeliverAnnouncement do
  use Oban.Worker,
    queue: :mailers,
    max_attempts: 5,
    unique: [
      fields: [:args],
      keys: [:slug, :recipient],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable, :completed, :discarded, :cancelled]
    ]

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
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Job{}), do: {:discard, "invalid args"}
end
