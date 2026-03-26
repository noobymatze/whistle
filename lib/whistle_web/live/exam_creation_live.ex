defmodule WhistleWeb.ExamCreationLive do
  use WhistleWeb, :live_view

  on_mount WhistleWeb.UserAuthLive

  alias Whistle.Courses
  alias Whistle.Registrations
  alias Whistle.Exams
  alias Whistle.Accounts.Role

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user = socket.assigns.current_user

    unless Role.admin?(user) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      course = Courses.get_course!(course_id)

      active_registrations =
        Registrations.registrations_for_course(course)
        |> Enum.reject(&(&1.unenrolled_at != nil))

      selected_ids = MapSet.new(active_registrations, & &1.user_id)

      distribution = Exams.get_distribution_for_course_type(course.type)

      {:ok,
       socket
       |> assign(:course, course)
       |> assign(:active_registrations, active_registrations)
       |> assign(:selected_ids, selected_ids)
       |> assign(:distribution, distribution)
       |> assign(:title, "Exam #{course.name}")
       |> assign(:error, nil)
       |> assign(:creating, false)}
    end
  end

  @impl true
  def handle_event("toggle_participant", %{"user-id" => user_id_str}, socket) do
    user_id = String.to_integer(user_id_str)
    selected = socket.assigns.selected_ids

    new_selected =
      if MapSet.member?(selected, user_id) do
        MapSet.delete(selected, user_id)
      else
        MapSet.put(selected, user_id)
      end

    {:noreply, assign(socket, :selected_ids, new_selected)}
  end

  @impl true
  def handle_event("toggle_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.active_registrations, & &1.user_id)
    current = socket.assigns.selected_ids

    new_selected =
      if MapSet.size(current) == MapSet.size(all_ids) do
        MapSet.new()
      else
        all_ids
      end

    {:noreply, assign(socket, :selected_ids, new_selected)}
  end

  @impl true
  def handle_event("update_title", %{"title" => title}, socket) do
    {:noreply, assign(socket, :title, title)}
  end

  @impl true
  def handle_event("create_exam", _params, socket) do
    user = socket.assigns.current_user
    course = socket.assigns.course
    user_ids = MapSet.to_list(socket.assigns.selected_ids)
    title = socket.assigns.title

    if Enum.empty?(user_ids) do
      {:noreply, assign(socket, :error, "Mindestens ein Teilnehmer muss ausgewählt sein.")}
    else
      socket = assign(socket, :creating, true)

      case Exams.create_exam(course, user_ids, user.id, title: title) do
        {:ok, _exam} ->
          {:noreply,
           socket
           |> put_flash(:info, "Exam wurde erfolgreich erstellt.")
           |> push_navigate(to: ~p"/admin/courses/#{course}/edit")}

        {:error, {:not_enough_questions, difficulty, needed, available}} ->
          msg =
            "Nicht genug Fragen (#{difficulty}): #{needed} benötigt, #{available} verfügbar."

          {:noreply,
           socket
           |> assign(:creating, false)
           |> assign(:error, msg)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:creating, false)
           |> assign(:error, "Fehler beim Erstellen des Exams: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <div class="mb-6">
        <.link href={~p"/admin/courses/#{@course}/edit"} class="text-sm text-blue-600 hover:underline">
          ← Zurück zum Kurs
        </.link>
        <h1 class="mt-2 text-2xl font-bold text-gray-900">Exam erstellen</h1>
        <p class="mt-1 text-sm text-gray-500">
          Kurs: {@course.name} · Typ: {@course.type}
        </p>
      </div>

      <%= if @error do %>
        <div class="mb-4 rounded-md bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">
          {@error}
        </div>
      <% end %>

      <%!-- Exam title --%>
      <div class="mb-6">
        <label class="block text-sm font-medium text-gray-700 mb-1">Titel</label>
        <input
          type="text"
          value={@title}
          phx-blur="update_title"
          phx-value-title={@title}
          name="title"
          class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
        />
      </div>

      <%!-- Distribution info --%>
      <div class="mb-6 rounded-md bg-gray-50 border border-gray-200 px-4 py-3">
        <h3 class="text-sm font-semibold text-gray-700 mb-1">Fragenverteilung (Kurstyp {@course.type})</h3>
        <% counts = Exams.calculate_difficulty_counts(@distribution.question_count, @distribution) %>
        <dl class="grid grid-cols-3 gap-2 text-sm text-gray-600">
          <div>
            <dt class="font-medium">Einfach</dt>
            <dd>{counts.low} Fragen ({@distribution.low_percentage}%)</dd>
          </div>
          <div>
            <dt class="font-medium">Mittel</dt>
            <dd>{counts.medium} Fragen ({@distribution.medium_percentage}%)</dd>
          </div>
          <div>
            <dt class="font-medium">Schwer</dt>
            <dd>{counts.high} Fragen ({@distribution.high_percentage}%)</dd>
          </div>
        </dl>
        <p class="mt-2 text-xs text-gray-500">
          Gesamt: {@distribution.question_count} Fragen ·
          Bestehensgrenze: {@distribution.pass_percentage}% ·
          Dauer: {div(@distribution.duration_seconds, 60)} Minuten
        </p>
      </div>

      <%!-- Participant selection --%>
      <div class="mb-6">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-sm font-semibold text-gray-700">
            Teilnehmende
            <span class="font-normal text-gray-500">
              ({MapSet.size(@selected_ids)} von {length(@active_registrations)} ausgewählt)
            </span>
          </h3>
          <button
            type="button"
            phx-click="toggle_all"
            class="text-sm text-blue-600 hover:underline"
          >
            <%= if MapSet.size(@selected_ids) == length(@active_registrations) do %>
              Alle abwählen
            <% else %>
              Alle auswählen
            <% end %>
          </button>
        </div>

        <%= if Enum.empty?(@active_registrations) do %>
          <p class="text-sm text-gray-500 italic">
            Keine aktiven Anmeldungen für diesen Kurs.
          </p>
        <% else %>
          <div class="divide-y divide-gray-100 border border-gray-200 rounded-md overflow-hidden">
            <%= for reg <- @active_registrations do %>
              <label class="flex items-center gap-3 px-4 py-3 hover:bg-gray-50 cursor-pointer">
                <input
                  type="checkbox"
                  checked={MapSet.member?(@selected_ids, reg.user_id)}
                  phx-click="toggle_participant"
                  phx-value-user-id={reg.user_id}
                  class="rounded border-gray-300 text-blue-600"
                />
                <span class="flex-1 text-sm">
                  {[reg.user_first_name, reg.user_last_name]
                  |> Enum.filter(& &1)
                  |> Enum.join(" ")}
                  <span class="text-gray-400 ml-1">{reg.user_email}</span>
                </span>
              </label>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Actions --%>
      <div class="flex items-center gap-3">
        <button
          type="button"
          phx-click="create_exam"
          disabled={@creating}
          class="inline-flex items-center rounded-md bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-500 disabled:opacity-60 disabled:cursor-not-allowed"
        >
          <%= if @creating do %>
            Wird erstellt…
          <% else %>
            Exam erstellen
          <% end %>
        </button>
        <.link
          href={~p"/admin/courses/#{@course}/edit"}
          class="text-sm text-gray-600 hover:underline"
        >
          Abbrechen
        </.link>
      </div>
    </div>
    """
  end
end
