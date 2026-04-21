defmodule WhistleWeb.MyCoursesLive do
  use WhistleWeb, :live_view
  import Ecto.Query
  alias Whistle.Repo
  alias Whistle.Courses
  alias Whistle.Registrations
  alias Whistle.Registrations.RegistrationView

  on_mount WhistleWeb.UserAuthLive

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    {registrations, date_selections, online_course_dates} = load_registrations(user.id)

    {:ok,
     assign(socket,
       registrations: registrations,
       date_selections: date_selections,
       online_course_dates: online_course_dates,
       editing_registration_id: nil,
       editing_date_selections: %{}
     )}
  end

  def handle_event("unenroll", %{"course_id" => course_id}, socket) do
    user = socket.assigns.current_user

    case Registrations.sign_out(String.to_integer(course_id), user.id, user.id) do
      {:ok, _} ->
        {registrations, date_selections, online_course_dates} = load_registrations(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Erfolgreich abgemeldet")
         |> assign(
           registrations: registrations,
           date_selections: date_selections,
           online_course_dates: online_course_dates,
           editing_registration_id: nil,
           editing_date_selections: %{}
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Fehler beim Abmelden")}
    end
  end

  def handle_event("start_reschedule", %{"registration_id" => registration_id}, socket) do
    registration_id = String.to_integer(registration_id)
    selections = Map.get(socket.assigns.date_selections, registration_id, [])

    editing_date_selections =
      selections
      |> Enum.reduce(%{}, fn %{date: date}, acc ->
        Map.put(acc, Atom.to_string(date.kind), date.id)
      end)

    {:noreply,
     assign(socket,
       editing_registration_id: registration_id,
       editing_date_selections: editing_date_selections
     )}
  end

  def handle_event("cancel_reschedule", _params, socket) do
    {:noreply, clear_reschedule(socket)}
  end

  def handle_event(
        "select_reschedule_date",
        %{"kind" => kind, "date_id" => date_id, "registration_id" => registration_id},
        socket
      ) do
    registration_id = String.to_integer(registration_id)
    date_id = String.to_integer(date_id)

    editing_date_selections =
      if socket.assigns.editing_registration_id == registration_id do
        Map.put(socket.assigns.editing_date_selections, kind, date_id)
      else
        socket.assigns.editing_date_selections
      end

    {:noreply, assign(socket, editing_date_selections: editing_date_selections)}
  end

  def handle_event("save_reschedule", %{"registration_id" => registration_id}, socket) do
    registration_id = String.to_integer(registration_id)
    user = socket.assigns.current_user

    if registration_id != socket.assigns.editing_registration_id do
      {:noreply,
       socket
       |> put_flash(:error, "Bitte öffne die Terminbearbeitung erneut.")
       |> clear_reschedule()}
    else
      case Registrations.reschedule_online_dates(
             user,
             registration_id,
             socket.assigns.editing_date_selections,
             user.id
           ) do
        {:ok, _registration} ->
          {registrations, date_selections, online_course_dates} = load_registrations(user.id)

          {:noreply,
           socket
           |> put_flash(:info, "Termine erfolgreich geändert")
           |> assign(
             registrations: registrations,
             date_selections: date_selections,
             online_course_dates: online_course_dates
           )
           |> clear_reschedule()}

        {:error, {:invalid_selection, _}} ->
          {:noreply,
           socket
           |> put_flash(:error, "Bitte wähle einen Pflicht- und einen Wahlpflichttermin.")
           |> assign(:editing_registration_id, registration_id)}

        {:error, {:not_available, _date}} ->
          {:noreply,
           socket
           |> put_flash(:error, "Der gewählte Termin ist ausgebucht.")
           |> assign(:editing_registration_id, registration_id)}

        {:error, :not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "Anmeldung nicht gefunden.")
           |> clear_reschedule()}

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Fehler beim Ändern der Termine")
           |> assign(:editing_registration_id, registration_id)}
      end
    end
  end

  defp type_badge_color(type) do
    case type do
      "F" -> "bg-blue-100 text-blue-800 border-blue-300"
      "J" -> "bg-green-100 text-green-800 border-green-300"
      "G" -> "bg-purple-100 text-purple-800 border-purple-300"
      _ -> "bg-gray-100 text-gray-800 border-gray-300"
    end
  end

  defp load_registrations(user_id) do
    regs =
      from(r in RegistrationView,
        where: r.user_id == ^user_id,
        order_by: [desc: r.year, desc: r.course_date]
      )
      |> Repo.all()

    date_selections =
      regs
      |> Enum.filter(& &1.course_online)
      |> Map.new(fn r ->
        {r.registration_id, Courses.list_date_selections_for_registration(r.registration_id)}
      end)

    online_course_dates =
      regs
      |> Enum.filter(&(&1.course_online and is_nil(&1.unenrolled_at)))
      |> Enum.map(& &1.course_id)
      |> Enum.uniq()
      |> Map.new(fn course_id ->
        course = Courses.get_course!(course_id)
        {course_id, Courses.list_course_dates_with_topics(course)}
      end)

    {Enum.group_by(regs, & &1.year), date_selections, online_course_dates}
  end

  defp clear_reschedule(socket) do
    assign(socket, editing_registration_id: nil, editing_date_selections: %{})
  end

  defp editing_selection_complete?(editing_date_selections) do
    Map.has_key?(editing_date_selections, "mandatory") and
      Map.has_key?(editing_date_selections, "elective")
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= for {year, registrations} <- @registrations |> Enum.sort_by(fn {year, _} -> year end, :desc) do %>
        <div>
          <h3 class="text-2xl font-semibold mb-4">Saison {year}</h3>
          <div class="grid gap-4 md:grid-cols-2">
            <%= for registration <- registrations do %>
              <% selections = Map.get(@date_selections, registration.registration_id, []) %>
              <% editing = @editing_registration_id == registration.registration_id %>
              <% available_dates = Map.get(@online_course_dates, registration.course_id, []) %>
              <% mandatory_dates = Enum.filter(available_dates, &(&1.kind == :mandatory)) %>
              <% elective_dates = Enum.filter(available_dates, &(&1.kind == :elective)) %>
              <% topics = Enum.group_by(elective_dates, & &1.course_date_topic_id) %>
              <div class={"rounded-lg border border-zinc-200 p-4 shadow-sm " <> if registration.unenrolled_at, do: "bg-zinc-100 opacity-60", else: "bg-white"}>
                <div class="flex gap-3">
                  <div class="flex-1">
                    <h4 class="font-bold text-base mb-3">{registration.course_name}</h4>
                    <div class="text-sm text-zinc-600 space-y-1">
                      <%= if registration.course_online do %>
                        <div class="flex items-center gap-2">
                          <.icon name="hero-users" class="h-4 w-4" /> Online
                        </div>
                      <% else %>
                        <%= if registration.course_date do %>
                          <div class="flex items-center gap-2">
                            <.icon name="hero-calendar" class="h-4 w-4" />
                            {Calendar.strftime(registration.course_date, "%d.%m.%Y")}
                          </div>
                        <% end %>
                        <%= if registration.organizer_name do %>
                          <div class="flex items-center gap-2">
                            <.icon name="hero-map-pin" class="h-4 w-4" />
                            {registration.organizer_name}
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex flex-col items-end gap-2">
                    <%= if is_nil(registration.unenrolled_at) do %>
                      <span class="text-xs text-green-700 font-medium bg-green-50 border border-green-200 rounded-full px-2 py-0.5">
                        Angemeldet
                      </span>
                    <% end %>
                    <div class="flex items-center gap-1">
                      <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border " <> type_badge_color(registration.course_type)}>
                        {registration.course_type}
                      </span>
                      <%= if registration.course_online do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border bg-orange-100 text-orange-800 border-orange-300">
                          Online
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>

                <%= if registration.course_online and is_nil(registration.unenrolled_at) and selections != [] do %>
                  <div class="mt-4 pt-4 border-t border-zinc-100 space-y-2">
                    <%= for %{date: date, topic: topic} <- selections do %>
                      <div class="flex items-start gap-2 text-sm text-zinc-600">
                        <.icon
                          name={
                            if date.kind == :mandatory, do: "hero-calendar", else: "hero-bookmark"
                          }
                          class="h-4 w-4 mt-0.5 flex-shrink-0"
                        />
                        <div>
                          <span>
                            {Calendar.strftime(date.date, "%d.%m.%Y")} · {Time.to_string(date.time)
                            |> String.slice(0, 5)} Uhr
                          </span>
                          <%= if topic do %>
                            <span class="ml-1 text-zinc-400">({topic.name})</span>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if editing and registration.course_online and is_nil(registration.unenrolled_at) do %>
                  <div
                    id={"reschedule-panel-#{registration.registration_id}"}
                    class="mt-4 rounded-xl border border-blue-200 bg-blue-50/60 p-4"
                  >
                    <div class="space-y-4">
                      <div>
                        <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500 mb-2">
                          Pflichttermin
                        </p>
                        <div class="space-y-1">
                          <%= for date <- mandatory_dates do %>
                            <label class="flex items-center gap-2 cursor-pointer">
                              <input
                                id={"reschedule-mandatory-#{registration.registration_id}-#{date.id}"}
                                type="radio"
                                name={"reschedule_mandatory_#{registration.registration_id}"}
                                phx-click="select_reschedule_date"
                                phx-value-registration_id={registration.registration_id}
                                phx-value-kind="mandatory"
                                phx-value-date_id={date.id}
                                checked={Map.get(@editing_date_selections, "mandatory") == date.id}
                                class="h-4 w-4"
                              />
                              <span class="text-sm">
                                {Calendar.strftime(date.date, "%d.%m.%Y")} · {Time.to_string(
                                  date.time
                                )
                                |> String.slice(0, 5)} Uhr
                              </span>
                            </label>
                          <% end %>
                        </div>
                      </div>

                      <div>
                        <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500 mb-2">
                          Wahlpflichttermin
                        </p>
                        <%= for {_topic_id, topic_dates} <- topics do %>
                          <% topic = hd(topic_dates).topic %>
                          <div class="mb-2">
                            <%= if topic do %>
                              <p class="text-xs text-zinc-400 mb-1">{topic.name}</p>
                            <% end %>
                            <div class="space-y-1">
                              <%= for date <- topic_dates do %>
                                <label class="flex items-center gap-2 cursor-pointer">
                                  <input
                                    id={"reschedule-elective-#{registration.registration_id}-#{date.id}"}
                                    type="radio"
                                    name={"reschedule_elective_#{registration.registration_id}"}
                                    phx-click="select_reschedule_date"
                                    phx-value-registration_id={registration.registration_id}
                                    phx-value-kind="elective"
                                    phx-value-date_id={date.id}
                                    checked={Map.get(@editing_date_selections, "elective") == date.id}
                                    class="h-4 w-4"
                                  />
                                  <span class="text-sm">
                                    {Calendar.strftime(date.date, "%d.%m.%Y")} · {Time.to_string(
                                      date.time
                                    )
                                    |> String.slice(0, 5)} Uhr
                                  </span>
                                </label>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>

                      <%= if not editing_selection_complete?(@editing_date_selections) do %>
                        <p class="text-xs text-amber-600">
                          Bitte wähle einen Pflicht- und einen Wahlpflichttermin.
                        </p>
                      <% end %>

                      <div class="flex flex-wrap justify-end gap-2">
                        <.button
                          type="button"
                          phx-click="cancel_reschedule"
                          class="btn-sm"
                        >
                          Abbrechen
                        </.button>
                        <.button
                          id={"save-reschedule-#{registration.registration_id}"}
                          type="button"
                          phx-click="save_reschedule"
                          phx-value-registration_id={registration.registration_id}
                          class="btn-sm"
                        >
                          Termine speichern
                        </.button>
                      </div>
                    </div>
                  </div>
                <% end %>

                <div class="mt-4 flex justify-end">
                  <%= if registration.unenrolled_at do %>
                    <div class="text-sm text-zinc-500">
                      Abgemeldet am {Whistle.Timezone.format_local(
                        registration.unenrolled_at,
                        "%d.%m.%Y"
                      )}
                    </div>
                  <% else %>
                    <div class="flex flex-wrap items-center justify-end gap-4">
                      <%= if registration.course_online do %>
                        <.link
                          id={"edit-reschedule-#{registration.registration_id}"}
                          phx-click={if editing, do: "cancel_reschedule", else: "start_reschedule"}
                          phx-value-registration_id={registration.registration_id}
                          class="underline font-bold text-sm"
                        >
                          {if editing, do: "Bearbeitung abbrechen", else: "Termin ändern"}
                        </.link>
                      <% end %>
                      <.link
                        phx-click="unenroll"
                        phx-value-course_id={registration.course_id}
                        data-confirm="Möchten Sie sich wirklich von diesem Kurs abmelden?"
                        class="underline font-bold text-sm"
                      >
                        Abmelden
                      </.link>
                    </div>
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
