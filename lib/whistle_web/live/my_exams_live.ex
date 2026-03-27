defmodule WhistleWeb.MyExamsLive do
  use WhistleWeb, :live_view
  import Ecto.Query
  alias Whistle.Repo
  alias Whistle.Exams.{Exam, ExamParticipant}

  on_mount WhistleWeb.UserAuthLive

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    exams = load_exams(user.id)

    {:ok, assign(socket, exams: exams)}
  end

  defp load_exams(user_id) do
    from(ep in ExamParticipant,
      join: e in Exam,
      on: ep.exam_id == e.id,
      where: ep.user_id == ^user_id,
      where: e.state not in ["canceled"],
      order_by: [desc: e.created_at],
      select: %{
        exam_id: e.id,
        course_type: e.course_type,
        state: e.state,
        started_at: e.started_at,
        exam_outcome: ep.exam_outcome,
        achieved_points: ep.achieved_points,
        max_points: ep.max_points
      }
    )
    |> Repo.all()
  end

  defp state_label("waiting_room"), do: "Warteraum"
  defp state_label("running"), do: "Läuft"
  defp state_label("paused"), do: "Pausiert"
  defp state_label("finished"), do: "Beendet"
  defp state_label(_), do: "Unbekannt"

  defp state_class("waiting_room"), do: "bg-yellow-100 text-yellow-800"
  defp state_class("running"), do: "bg-green-100 text-green-800"
  defp state_class("paused"), do: "bg-orange-100 text-orange-800"
  defp state_class("finished"), do: "bg-zinc-100 text-zinc-600"
  defp state_class(_), do: "bg-zinc-100 text-zinc-600"

  defp outcome_label("l1_eligible"), do: {"Bestanden (L1-Prüfung ausstehend)", :pass}
  defp outcome_label("l2_pass"), do: {"Bestanden (L2)", :pass}
  defp outcome_label("l3_pass"), do: {"Bestanden (L3)", :pass}
  defp outcome_label("fail"), do: {"Nicht bestanden", :fail}
  defp outcome_label(_), do: nil

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @exams == [] do %>
        <div class="text-center py-12 text-zinc-500">
          <.icon name="hero-clipboard-document-list" class="h-16 w-16 mx-auto mb-4 opacity-50" />
          <p>Keine Tests zugewiesen.</p>
        </div>
      <% else %>
        <div class="grid gap-4 md:grid-cols-2">
          <%= for exam <- @exams do %>
            <div class="rounded-lg border p-4 shadow-sm bg-white">
              <div class="flex items-center justify-between mb-2">
                <h4 class="text-lg font-bold">{exam.course_type}-Kurs Prüfung</h4>
                <span class={"inline-flex rounded-full px-2 py-0.5 text-xs font-medium " <> state_class(exam.state)}>
                  {state_label(exam.state)}
                </span>
              </div>

              <%= if exam.started_at do %>
                <div class="text-sm text-zinc-500 mb-3">
                  <.icon name="hero-calendar" class="h-4 w-4 inline mr-1" />
                  {Calendar.strftime(exam.started_at, "%d.%m.%Y")}
                </div>
              <% end %>

              <%= if {label, kind} = outcome_label(exam.exam_outcome) do %>
                <div class="text-sm mb-3">
                  <span class={if kind == :pass, do: "text-green-700 font-medium", else: "text-red-700 font-medium"}>
                    {label}
                  </span>
                  <%= if exam.achieved_points && exam.max_points do %>
                    <span class="text-zinc-500 ml-1">({exam.achieved_points}/{exam.max_points} Punkte)</span>
                  <% end %>
                </div>
              <% end %>

              <%= if exam.state in ["waiting_room", "running"] do %>
                <div class="flex justify-end mt-2">
                  <.link navigate={~p"/exams/#{exam.exam_id}"} class="underline font-bold text-sm">
                    Zum Test →
                  </.link>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
