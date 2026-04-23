defmodule Whistle.AccountsMailDeliveryTest do
  use Whistle.DataCase, async: false

  import Whistle.AccountsFixtures

  alias Whistle.Accounts
  alias Whistle.Accounts.UserToken
  alias Whistle.Repo

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

  test "confirmation delivery failure does not leave behind a token" do
    user = user_fixture()

    assert {:error, :smtp_unavailable} =
             Accounts.deliver_user_confirmation_instructions(user, fn token ->
               "https://example.com/confirm/#{token}"
             end)

    refute Repo.get_by(UserToken, user_id: user.id, context: "confirm")
  end

  test "reset password delivery failure does not leave behind a token" do
    user = user_fixture()

    assert {:error, :smtp_unavailable} =
             Accounts.deliver_user_reset_password_instructions(user, fn token ->
               "https://example.com/reset/#{token}"
             end)

    refute Repo.get_by(UserToken, user_id: user.id, context: "reset_password")
  end

  test "email change delivery failure does not leave behind a token" do
    user = user_fixture()

    assert {:error, :smtp_unavailable} =
             Accounts.deliver_user_update_email_instructions(
               user,
               user.email,
               fn token -> "https://example.com/change/#{token}" end
             )

    refute Repo.get_by(UserToken, user_id: user.id, context: "change:#{user.email}")
  end
end
