defmodule Whistle.Workers.PruneExpiredPendingUsersTest do
  use Whistle.DataCase, async: true
  use Oban.Testing, repo: Whistle.Repo

  import Whistle.AccountsFixtures

  alias Whistle.Accounts.PendingUser
  alias Whistle.Repo
  alias Whistle.Workers.PruneExpiredPendingUsers

  test "deletes expired pending users" do
    {pending_user, _token} = pending_user_fixture()

    {1, nil} =
      Repo.update_all(
        from(p in PendingUser, where: p.id == ^pending_user.id),
        set: [expires_at: ~N[2020-01-01 00:00:00]]
      )

    assert :ok = perform_job(PruneExpiredPendingUsers, %{})
    refute Repo.get(PendingUser, pending_user.id)
  end
end
