defmodule WhistleWeb.AuthMailObanSmokeTest do
  use WhistleWeb.ConnCase, async: false
  use Oban.Testing, repo: Whistle.Repo

  import Swoosh.TestAssertions
  import Whistle.AccountsFixtures

  alias Oban.Job
  alias Phoenix.Flash
  alias Whistle.Accounts
  alias Whistle.Repo
  alias Whistle.Workers.DeliverUserEmail

  test "registration and password reset emails flow through Oban and are visible to super admins",
       %{conn: conn} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      user_params = %{
        "username" => unique_username(),
        "email" => unique_user_email(),
        "password" => valid_user_password(),
        "first_name" => "Smoke",
        "last_name" => "Test",
        "birthday" => "1990-01-01"
      }

      conn = post(conn, ~p"/users/register", %{"user" => user_params})

      assert redirected_to(conn) == "/"
      assert Flash.get(conn.assigns.flash, :info) == "Benutzer erfolgreich erstellt."

      confirm_job = fetch_mail_job!("confirm")
      assert confirm_job.args["recipient"] == user_params["email"]

      assert :ok = perform_job(DeliverUserEmail, confirm_job.args)

      assert_email_sent(fn email ->
        recipient?(email, user_params["email"]) and
          email.subject == "E-Mail Bestätigung" and
          email.text_body =~ "/users/confirm/"
      end)

      mark_job_completed!(confirm_job)

      conn =
        post(build_conn(), ~p"/users/reset_password", %{
          "user" => %{"username_or_email" => user_params["username"]}
        })

      assert redirected_to(conn) == "/"
      assert Flash.get(conn.assigns.flash, :info) =~ "erhältst du in Kürze Anweisungen"

      reset_job = fetch_mail_job!("reset_password")
      assert reset_job.args["recipient"] == user_params["email"]

      assert :ok = perform_job(DeliverUserEmail, reset_job.args)

      assert_email_sent(fn email ->
        recipient?(email, user_params["email"]) and
          email.subject == "Passwort-Zurücksetzen Anweisungen" and
          email.text_body =~ "/users/reset_password/"
      end)

      reset_job = mark_job_discarded!(reset_job, "smtp smoke failure")
      super_admin = user_fixture(%{role: "SUPER_ADMIN"})

      conn =
        build_conn()
        |> log_in(super_admin)
        |> get(~p"/admin/jobs")

      html = html_response(conn, 200)
      assert html =~ "Jobs"
      assert html =~ "Whistle.Workers.DeliverUserEmail"
      assert html =~ user_params["email"]
      assert html =~ "confirm"
      assert html =~ "reset_password"

      conn =
        build_conn()
        |> log_in(super_admin)
        |> get(~p"/admin/jobs?state=discarded")

      html = html_response(conn, 200)
      assert html =~ "smtp smoke failure"
      assert html =~ "reset_password"

      conn =
        build_conn()
        |> log_in(super_admin)
        |> post(~p"/admin/jobs/#{reset_job.id}/retry")

      assert redirected_to(conn) == "/admin/jobs"
      assert Flash.get(conn.assigns.flash, :info) =~ "erneut"

      reset_job = Repo.get!(Job, reset_job.id)
      assert reset_job.state in ["available", "scheduled"]

      admin = user_fixture(%{role: "ADMIN"})

      conn =
        build_conn()
        |> log_in(admin)
        |> get(~p"/admin/jobs")

      assert redirected_to(conn) == "/"
      assert Flash.get(conn.assigns.flash, :error) =~ "keine Berechtigung"
    end)
  end

  defp fetch_mail_job!(type) do
    all_enqueued(worker: DeliverUserEmail, queue: :mailers)
    |> Enum.find(&(&1.args["type"] == type))
    |> case do
      %Job{} = job -> job
      nil -> flunk("expected an enqueued #{type} mail job")
    end
  end

  defp mark_job_completed!(%Job{} = job) do
    now = DateTime.utc_now()

    job
    |> Ecto.Changeset.change(state: "completed", completed_at: now)
    |> Repo.update!()
  end

  defp mark_job_discarded!(%Job{} = job, error) do
    now = DateTime.utc_now()

    job
    |> Ecto.Changeset.change(
      state: "discarded",
      discarded_at: now,
      errors: [%{"error" => error, "at" => DateTime.to_iso8601(now)}]
    )
    |> Repo.update!()
  end

  defp recipient?(email, expected) do
    Enum.any?(email.to, fn
      {_name, ^expected} -> true
      ^expected -> true
      _ -> false
    end)
  end

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end
end
