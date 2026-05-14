defmodule Whistle.Workers.PruneUnconfirmedUsersTest do
  use Whistle.DataCase, async: true
  use Oban.Testing, repo: Whistle.Repo

  import Whistle.AccountsFixtures

  alias Whistle.Accounts
  alias Whistle.Accounts.User
  alias Whistle.Repo
  alias Whistle.Workers.PruneUnconfirmedUsers

  test "deletes expired unconfirmed users" do
    {:ok, user} = Accounts.register_user(valid_user_attributes())

    {1, nil} =
      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [created_at: ~N[2020-01-01 00:00:00]]
      )

    assert :ok = perform_job(PruneUnconfirmedUsers, %{})
    refute Repo.get(User, user.id)
  end
end
