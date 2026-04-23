defmodule WhistleWeb.JobControllerTest do
  use WhistleWeb.ConnCase, async: false
  use Oban.Testing, repo: Whistle.Repo

  import Whistle.AccountsFixtures

  alias Oban.Job
  alias Whistle.Accounts
  alias Phoenix.Flash
  alias Whistle.Repo
  alias Whistle.Workers.DeliverUserEmail

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  test "SUPER_ADMIN can see all jobs and filter by state", %{conn: conn} do
    super_admin = user_fixture(%{role: "SUPER_ADMIN"})

    job =
      Oban.Testing.with_testing_mode(:manual, fn ->
        DeliverUserEmail.new(%{
          recipient: "person@example.com",
          type: "confirm",
          url: "https://example.com/confirm/token",
          username: "person"
        })
        |> Whistle.Oban.insert!()
      end)

    Repo.update!(Ecto.Changeset.change(job, state: "discarded", errors: [%{error: "boom"}]))

    conn = get(log_in(conn, super_admin), ~p"/admin/jobs?state=discarded")

    html = html_response(conn, 200)
    assert html =~ "Jobs"
    assert html =~ "discarded"
    assert html =~ "boom"
  end

  test "ADMIN cannot access the jobs admin", %{conn: conn} do
    admin = user_fixture(%{role: "ADMIN"})

    conn = get(log_in(conn, admin), ~p"/admin/jobs")

    assert redirected_to(conn) == "/"
  end

  test "SUPER_ADMIN can retry a failed job", %{conn: conn} do
    super_admin = user_fixture(%{role: "SUPER_ADMIN"})

    Oban.Testing.with_testing_mode(:manual, fn ->
      job =
        DeliverUserEmail.new(%{
          recipient: "retry@example.com",
          type: "confirm",
          url: "https://example.com/confirm/token",
          username: "retry-user"
        })
        |> Whistle.Oban.insert!()

      job =
        Repo.update!(
          Ecto.Changeset.change(job,
            state: "discarded",
            errors: [%{error: "smtp down"}],
            scheduled_at: DateTime.utc_now()
          )
        )

      conn = post(log_in(conn, super_admin), ~p"/admin/jobs/#{job.id}/retry")

      assert redirected_to(conn) == "/admin/jobs"
      assert Flash.get(conn.assigns.flash, :info) =~ "erneut"

      reloaded = Repo.get!(Job, job.id)
      assert reloaded.state in ["available", "scheduled"]
      assert reloaded.attempt == 0
    end)
  end
end
