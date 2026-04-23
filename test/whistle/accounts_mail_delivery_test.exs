defmodule Whistle.AccountsMailDeliveryTest do
  use Whistle.DataCase, async: false
  use Oban.Testing, repo: Whistle.Repo

  import Whistle.AccountsFixtures

  alias Whistle.Accounts
  alias Whistle.Accounts.UserToken
  alias Whistle.Repo
  alias Whistle.Workers.DeliverUserEmail

  setup do
    original_config = Application.get_env(:whistle, Whistle.Mailer)

    Application.put_env(
      :whistle,
      Whistle.Mailer,
      Keyword.merge(original_config || [], adapter: Whistle.TestSupport.FailingSwooshAdapter)
    )

    on_exit(fn ->
      Application.put_env(:whistle, Whistle.Mailer, original_config)
    end)

    :ok
  end

  test "confirmation instructions enqueue a mail job and persist the token" do
    user = user_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _job} =
               Accounts.deliver_user_confirmation_instructions(user, fn token ->
                 "https://example.com/confirm/#{token}"
               end)

      assert Repo.get_by(UserToken, user_id: user.id, context: "confirm")
      assert [job] = all_enqueued(worker: DeliverUserEmail, queue: :mailers)
      assert job.args["recipient"] == user.email
      assert job.args["type"] == "confirm"
      assert job.args["username"] == user.username
      assert String.starts_with?(job.args["url"], "https://example.com/confirm/")
    end)
  end

  test "reset password instructions enqueue a mail job and persist the token" do
    user = user_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _job} =
               Accounts.deliver_user_reset_password_instructions(user, fn token ->
                 "https://example.com/reset/#{token}"
               end)

      assert Repo.get_by(UserToken, user_id: user.id, context: "reset_password")
      assert [job] = all_enqueued(worker: DeliverUserEmail, queue: :mailers)
      assert job.args["recipient"] == user.email
      assert job.args["type"] == "reset_password"
      assert job.args["username"] == user.username
      assert String.starts_with?(job.args["url"], "https://example.com/reset/")
    end)
  end

  test "email change instructions enqueue a mail job and persist the token" do
    user = user_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _job} =
               Accounts.deliver_user_update_email_instructions(
                 user,
                 user.email,
                 fn token -> "https://example.com/change/#{token}" end
               )

      assert Repo.get_by(UserToken, user_id: user.id, context: "change:#{user.email}")
      assert [job] = all_enqueued(worker: DeliverUserEmail, queue: :mailers)
      assert job.args["recipient"] == user.email
      assert job.args["type"] == "change_email"
      assert job.args["username"] == user.username
      assert String.starts_with?(job.args["url"], "https://example.com/change/")
    end)
  end
end
