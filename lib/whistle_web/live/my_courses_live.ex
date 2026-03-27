defmodule WhistleWeb.MyCoursesLive do
  use WhistleWeb, :live_view
  import Ecto.Query
  alias Whistle.Repo
  alias Whistle.Registrations.RegistrationView
  alias Whistle.Exams.{Exam, ExamParticipant}

  on_mount WhistleWeb.UserAuthLive

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    registrations = load_registrations(user.id)
    exams = load_exams(user.id)

    {:ok, assign(socket, registrations: registrations, exams: exams)}
  end

  def handle_event("unenroll", %{"course_id" => course_id}, socket) do
    user = socket.assigns.current_user

    # Update the registration to mark as unenrolled
    query =
      from r in "registrations",
        where: r.user_id == ^user.id and r.course_id == ^course_id and is_nil(r.unenrolled_at),
        update: [
          set: [
            unenrolled_at: fragment("NOW()"),
            unenrolled_by: ^user.id
          ]
        ]

    case Repo.update_all(query, []) do
      {1, _} ->
        registrations = load_registrations(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Erfolgreich abgemeldet")
         |> assign(registrations: registrations)}

      _ ->
        {:noreply, put_flash(socket, :error, "Fehler beim Abmelden")}
    end
  end

  defp load_registrations(user_id) do
    query =
      from r in RegistrationView,
        where: r.user_id == ^user_id,
        order_by: [desc: r.year, desc: r.course_date]

    Repo.all(query)
    |> Enum.group_by(& &1.year)
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
        participant_state: ep.state,
        exam_outcome: ep.exam_outcome,
        achieved_points: ep.achieved_points,
        max_points: ep.max_points
      }
    )
    |> Repo.all()
  end

  defp exam_state_label("waiting_room"), do: "Warteraum"
  defp exam_state_label("running"), do: "Läuft"
  defp exam_state_label("paused"), do: "Pausiert"
  defp exam_state_label("finished"), do: "Beendet"
  defp exam_state_label(_), do: "Unbekannt"

  defp exam_state_class("waiting_room"), do: "bg-yellow-100 text-yellow-800"
  defp exam_state_class("running"), do: "bg-green-100 text-green-800"
  defp exam_state_class("paused"), do: "bg-orange-100 text-orange-800"
  defp exam_state_class("finished"), do: "bg-zinc-100 text-zinc-600"
  defp exam_state_class(_), do: "bg-zinc-100 text-zinc-600"

  defp outcome_label("l1_eligible"), do: "Bestanden (L1-Prüfung ausstehend)"
  defp outcome_label("l2_pass"), do: "Bestanden (L2)"
  defp outcome_label("l3_pass"), do: "Bestanden (L3)"
  defp outcome_label("fail"), do: "Nicht bestanden"
  defp outcome_label(_), do: nil

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= if @exams != [] do %>
        <div>
          <h3 class="text-2xl font-semibold mb-4">Meine Tests</h3>
          <div class="grid gap-4 md:grid-cols-2">
            <%= for exam <- @exams do %>
              <div class="rounded-lg border p-4 shadow-sm bg-white">
                <div class="flex items-center justify-between mb-2">
                  <h4 class="text-lg font-bold">{exam.course_type}-Kurs Prüfung</h4>
                  <span class={"inline-flex rounded-full px-2 py-0.5 text-xs font-medium " <> exam_state_class(exam.state)}>
                    {exam_state_label(exam.state)}
                  </span>
                </div>
                <%= if exam.started_at do %>
                  <div class="text-sm text-zinc-500 mb-3">
                    <.icon name="hero-calendar" class="h-4 w-4 inline mr-1" />
                    {Calendar.strftime(exam.started_at, "%d.%m.%Y")}
                  </div>
                <% end %>
                <%= if outcome = outcome_label(exam.exam_outcome) do %>
                  <div class="text-sm mb-3">
                    <span class={if String.starts_with?(outcome, "Bestanden"), do: "text-green-700 font-medium", else: "text-red-700 font-medium"}>
                      {outcome}
                    </span>
                    <%= if exam.achieved_points && exam.max_points do %>
                      <span class="text-zinc-500 ml-1">({exam.achieved_points}/{exam.max_points} Punkte)</span>
                    <% end %>
                  </div>
                <% end %>
                <%= if exam.state in ["waiting_room", "running"] do %>
                  <div class="flex justify-end">
                    <.link navigate={~p"/exams/#{exam.exam_id}"} class="underline font-bold text-sm">
                      Zum Test →
                    </.link>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= for {year, registrations} <- @registrations |> Enum.sort_by(fn {year, _} -> year end, :desc) do %>
        <div>
          <h3 class="text-2xl font-semibold mb-4">Saison {year}</h3>
          <div class="grid gap-4 md:grid-cols-2">
            <%= for registration <- registrations do %>
              <div class={"rounded-lg border p-4 shadow-sm " <> if registration.unenrolled_at, do: "bg-zinc-100 opacity-60", else: "bg-white"}>
                <h4 class="text-lg font-bold mb-2">{registration.course_name}</h4>
                <div class="text-sm text-zinc-600 mb-4">
                  <div class="flex items-center gap-2 mb-1">
                    <.icon name="hero-calendar" class="h-4 w-4" />
                    <%= if registration.course_date do %>
                      {Calendar.strftime(registration.course_date, "%d.%m.%Y")}
                    <% else %>
                      Termin noch nicht bekannt
                    <% end %>
                  </div>
                  <div class="flex items-center gap-2">
                    <.icon name="hero-map-pin" class="h-4 w-4" />
                    {registration.organizer_name}
                  </div>
                </div>

                <div class="flex justify-end">
                  <%= if registration.unenrolled_at do %>
                    <div class="text-sm text-zinc-500">
                      Abgemeldet am {Whistle.Timezone.format_local(
                        registration.unenrolled_at,
                        "%d.%m.%Y"
                      )}
                    </div>
                  <% else %>
                    <.link
                      phx-click="unenroll"
                      phx-value-course_id={registration.course_id}
                      data-confirm="Möchten Sie sich wirklich von diesem Kurs abmelden?"
                      class="underline font-bold text-sm"
                    >
                      Abmelden
                    </.link>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @registrations == %{} do %>
        <div class="text-center py-12 text-zinc-500">
          <.icon name="hero-academic-cap" class="h-16 w-16 mx-auto mb-4 opacity-50" />
          <p>Sie haben sich noch für keine Kurse angemeldet.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
