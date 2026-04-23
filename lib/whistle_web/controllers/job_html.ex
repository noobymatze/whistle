defmodule WhistleWeb.JobHTML do
  use WhistleWeb, :html

  embed_templates "job_html/*"

  def state_badge_class("available"), do: "bg-sky-100 text-sky-700"
  def state_badge_class("scheduled"), do: "bg-indigo-100 text-indigo-700"
  def state_badge_class("executing"), do: "bg-amber-100 text-amber-700"
  def state_badge_class("retryable"), do: "bg-orange-100 text-orange-700"
  def state_badge_class("completed"), do: "bg-emerald-100 text-emerald-700"
  def state_badge_class("cancelled"), do: "bg-zinc-100 text-zinc-600"
  def state_badge_class("discarded"), do: "bg-red-100 text-red-700"
  def state_badge_class("suspended"), do: "bg-violet-100 text-violet-700"
  def state_badge_class(_), do: "bg-zinc-100 text-zinc-600"

  def short_worker(nil), do: "–"
  def short_worker(worker), do: String.replace_prefix(worker, "Elixir.", "")

  def last_error_message(%{errors: errors}) when is_list(errors) do
    case List.last(errors) do
      %{"error" => message} -> message
      %{error: message} -> message
      %{} = error -> inspect(error)
      _ -> nil
    end
  end

  def last_error_message(_), do: nil

  def page_params(filters, page) do
    filters
    |> Map.put(:page, page)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
