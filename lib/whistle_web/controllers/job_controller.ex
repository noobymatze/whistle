defmodule WhistleWeb.JobController do
  use WhistleWeb, :controller

  alias Whistle.Jobs

  plug WhistleWeb.Plugs.RequireRole, role: "SUPER_ADMIN"

  def index(conn, params) do
    job_page = Jobs.list_jobs(params)

    conn
    |> assign(:wide_layout, true)
    |> render(:index,
      jobs: job_page.jobs,
      page: job_page.page,
      per_page: job_page.per_page,
      total_count: job_page.total_count,
      total_pages: job_page.total_pages,
      filters: job_page.filters,
      states: job_page.states,
      queues: job_page.queues,
      workers: job_page.workers
    )
  end

  def retry(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, _job} <- do_retry_job(id) do
      conn
      |> put_flash(:info, "Job wurde erneut zur Ausführung vorgemerkt.")
      |> redirect(to: ~p"/admin/jobs?#{retry_redirect_params(conn)}")
    else
      _ ->
        conn
        |> put_flash(:error, "Job konnte nicht erneut vorgemerkt werden.")
        |> redirect(to: ~p"/admin/jobs?#{retry_redirect_params(conn)}")
    end
  end

  defp do_retry_job(id) do
    case Jobs.retry_job(id) do
      {:ok, job} -> {:ok, job}
      :error -> :error
    end
  end

  defp retry_redirect_params(conn) do
    conn.query_params
    |> Map.take(["page", "queue", "state", "worker"])
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
