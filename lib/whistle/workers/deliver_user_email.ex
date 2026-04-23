defmodule Whistle.Workers.DeliverUserEmail do
  use Oban.Worker, queue: :mailers, max_attempts: 5

  alias Oban.Job
  alias Whistle.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Job{
        args: %{
          "recipient" => recipient,
          "type" => type,
          "url" => url,
          "username" => username
        }
      }) do
    user = %{email: recipient, username: username}

    case deliver(user, type, url) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Job{}), do: {:discard, "invalid args"}

  defp deliver(user, "confirm", url),
    do: UserNotifier.deliver_confirmation_instructions(user, url)

  defp deliver(user, "reset_password", url),
    do: UserNotifier.deliver_reset_password_instructions(user, url)

  defp deliver(user, "change_email", url),
    do: UserNotifier.deliver_update_email_instructions(user, url)

  defp deliver(_user, type, _url), do: {:error, "unsupported email type: #{type}"}
end
