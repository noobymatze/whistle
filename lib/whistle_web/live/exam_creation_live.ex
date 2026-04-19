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

    unless Role.can_access_course_area?(user) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      course = Courses.get_course!(course_id)

      active_registrations =
        Registrations.registrations_for_course(course)
        |> Enum.reject(&(&1.unenrolled_at != nil))

      selected_ids = MapSet.new(active_registrations, & &1.user_id)

      distribution = Exams.get_distribution_for_course_type(course.type)
      questions_result = Exams.select_questions_for_course_type(course.type)

      {selected_questions, questions_error} =
        case questions_result do
          {:ok, qs} -> {qs, nil}
          {:error, reason} -> {[], reason}
        end

      {:ok,
       socket
       |> assign(:course, course)
       |> assign(:active_registrations, active_registrations)
       |> assign(:selected_ids, selected_ids)
       |> assign(:distribution, distribution)
       |> assign(:selected_questions, selected_questions)
       |> assign(:error, format_questions_error(questions_error))
       |> assign(:creating, false)
       |> assign(:execution_mode, "synchronous")}
    end
  end

  @impl true
  def handle_event("set_execution_mode", %{"mode" => mode}, socket)
      when mode in ["synchronous", "asynchronous"] do
    {:noreply, assign(socket, :execution_mode, mode)}
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
  def handle_event("create_exam", _params, socket) do
    user = socket.assigns.current_user
    course = socket.assigns.course
    user_ids = MapSet.to_list(socket.assigns.selected_ids)

    if Enum.empty?(user_ids) do
      {:noreply, assign(socket, :error, "Mindestens ein Teilnehmer muss ausgewählt sein.")}
    else
      socket = assign(socket, :creating, true)

      case Exams.create_exam(course, user_ids, user.id,
             questions: socket.assigns.selected_questions,
             execution_mode: socket.assigns.execution_mode
           ) do
        {:ok, _exam} ->
          {:noreply,
           socket
           |> put_flash(:info, "Test wurde erfolgreich erstellt.")
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
           |> assign(:error, "Fehler beim Erstellen des Tests: #{inspect(reason)}")}
      end
    end
  end

  defp format_questions_error(nil), do: nil

  defp format_questions_error({:not_enough_questions, difficulty, needed, available}) do
    "Nicht genug Fragen (#{difficulty}): #{needed} benötigt, #{available} verfügbar."
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item navigate={~p"/admin/courses"}>Kurse</:item>
      <:item navigate={~p"/admin/courses/#{@course}/edit"}>{@course.name}</:item>
      <:item>Test erstellen</:item>
    </.breadcrumbs>

    <.header class="mt-4">
      Test erstellen
      <:subtitle>Kurs: {@course.name} · Typ: {@course.type}</:subtitle>
    </.header>

    <.error :if={@error}>{@error}</.error>

    <div class="mt-6 space-y-8 max-w-2xl">
      <%!-- Distribution info --%>
      <div class="rounded-md bg-gray-50 border border-gray-200 px-4 py-3">
        <h3 class="text-sm font-semibold text-gray-700 mb-1">
          Fragenverteilung (Kurstyp {@course.type})
        </h3>
        <p class="mt-1 text-xs text-gray-500">
          {@distribution.question_count} Fragen ·
          Dauer: {div(@distribution.duration_seconds, 60)} Minuten
        </p>
      </div>

      <%!-- Execution mode selection --%>
      <div>
        <h3 class="text-sm font-semibold text-gray-700 mb-2">Durchführungsmodus</h3>
        <div class="flex gap-2">
          <button
            id="execution-mode-sync"
            type="button"
            phx-click="set_execution_mode"
            phx-value-mode="synchronous"
            class={[
              "px-4 py-2 rounded-md text-sm font-medium border transition-colors",
              @execution_mode == "synchronous" &&
                "bg-blue-600 text-white border-blue-600",
              @execution_mode != "synchronous" &&
                "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
            ]}
          >
            Synchron (Gruppenstart)
          </button>
          <button
            id="execution-mode-async"
            type="button"
            phx-click="set_execution_mode"
            phx-value-mode="asynchronous"
            class={[
              "px-4 py-2 rounded-md text-sm font-medium border transition-colors",
              @execution_mode == "asynchronous" &&
                "bg-blue-600 text-white border-blue-600",
              @execution_mode != "asynchronous" &&
                "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
            ]}
          >
            Asynchron (Einzelstart, 30 Min.)
          </button>
        </div>
      </div>

      <%!-- Participant selection --%>
      <div>
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-sm font-semibold text-gray-700">
            Teilnehmende
            <span class="font-normal text-gray-500">
              ({MapSet.size(@selected_ids)} von {length(@active_registrations)} ausgewählt)
            </span>
          </h3>
          <.button type="button" phx-click="toggle_all">
            <%= if MapSet.size(@selected_ids) == length(@active_registrations) do %>
              Alle abwählen
            <% else %>
              Alle auswählen
            <% end %>
          </.button>
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
      <div>
        <.button type="button" phx-click="create_exam" disabled={@creating}>
          <%= if @creating do %>
            Wird erstellt…
          <% else %>
            Test erstellen
          <% end %>
        </.button>
      </div>

      <%!-- Selected questions preview --%>
      <div>
        <h3 class="text-sm font-semibold text-gray-700 mb-2">
          Ausgewählte Fragen
          <span class="font-normal text-gray-500">({length(@selected_questions)} Fragen)</span>
        </h3>
        <div class="divide-y divide-gray-100 border border-gray-200 rounded-md overflow-hidden">
          <%= for {q, i} <- Enum.with_index(@selected_questions, 1) do %>
            <div class="flex items-center gap-3 px-4 py-2 text-sm">
              <span class="text-gray-400 w-5 text-right flex-shrink-0">{i}</span>
              <span class={[
                "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium flex-shrink-0",
                q.difficulty == "low" && "bg-green-100 text-green-700",
                q.difficulty == "medium" && "bg-yellow-100 text-yellow-700",
                q.difficulty == "high" && "bg-red-100 text-red-700"
              ]}>
                {case q.difficulty do
                  "low" -> "Einfach"
                  "medium" -> "Mittel"
                  "high" -> "Schwer"
                  d -> d
                end}
              </span>
              <span class="truncate text-gray-700">{q.body_markdown}</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
