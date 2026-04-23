defmodule Whistle.Jobs do
  @moduledoc """
  Query and admin helpers for Oban jobs.
  """

  import Ecto.Query, warn: false

  alias Oban.Job
  alias Whistle.Oban
  alias Whistle.Repo

  @per_page 50

  def list_jobs(params \\ %{}) do
    page = parse_page(params["page"])
    filters = normalize_filters(params)
    query = filtered_jobs_query(filters)
    total_count = Repo.aggregate(query, :count)
    total_pages = max(div(total_count + @per_page - 1, @per_page), 1)
    current_page = min(page, total_pages)

    jobs =
      query
      |> limit(^@per_page)
      |> offset(^((current_page - 1) * @per_page))
      |> Repo.all()

    %{
      jobs: jobs,
      page: current_page,
      per_page: @per_page,
      total_count: total_count,
      total_pages: total_pages,
      filters: filters,
      states: Enum.map(Job.states(), &Atom.to_string/1),
      queues: distinct_values(:queue),
      workers: distinct_values(:worker)
    }
  end

  def get_job(id), do: Repo.get(Job, id)

  def retry_job(%Job{} = job) do
    :ok = Oban.retry_job(job)
    {:ok, Repo.get(Job, job.id)}
  end

  def retry_job(id) when is_integer(id) do
    case get_job(id) do
      %Job{} = job -> retry_job(job)
      nil -> :error
    end
  end

  def filtered_jobs_query(filters) do
    Job
    |> order_by([job], desc: job.inserted_at, desc: job.id)
    |> maybe_filter_state(filters.state)
    |> maybe_filter_queue(filters.queue)
    |> maybe_filter_worker(filters.worker)
  end

  defp maybe_filter_state(query, ""), do: query
  defp maybe_filter_state(query, state), do: where(query, [job], job.state == ^state)

  defp maybe_filter_queue(query, ""), do: query
  defp maybe_filter_queue(query, queue), do: where(query, [job], job.queue == ^queue)

  defp maybe_filter_worker(query, ""), do: query

  defp maybe_filter_worker(query, worker) do
    pattern = "%#{worker}%"
    where(query, [job], ilike(job.worker, ^pattern))
  end

  defp distinct_values(field) do
    query =
      case field do
        :queue ->
          from job in Job,
            select: job.queue,
            distinct: true,
            order_by: [asc: job.queue]

        :worker ->
          from job in Job,
            select: job.worker,
            distinct: true,
            order_by: [asc: job.worker]
      end

    query
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_filters(params) do
    %{
      state: normalize_filter(params["state"]),
      queue: normalize_filter(params["queue"]),
      worker: normalize_filter(params["worker"])
    }
  end

  defp normalize_filter(nil), do: ""
  defp normalize_filter(value), do: String.trim(value)

  defp parse_page(nil), do: 1

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
