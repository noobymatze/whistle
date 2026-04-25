defmodule WhistleWeb.ExamCreationLive do
  use WhistleWeb, :live_view

  alias Whistle.Courses
  alias Whistle.Registrations
  alias Whistle.Exams

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    course = Courses.get_course!(course_id)

    active_registrations =
      Registrations.registrations_for_course(course)
      |> Enum.reject(&(&1.unenrolled_at != nil))

    selected_ids = MapSet.new(active_registrations, & &1.user_id)
    variants = Exams.list_enabled_exam_variants(course.type)

    {:ok,
     socket
     |> assign(:course, course)
     |> assign(:active_registrations, active_registrations)
     |> assign(:selected_ids, selected_ids)
     |> assign(:variants, variants)
     |> assign(:selected_variant, nil)
     |> assign(:selected_questions, [])
     |> assign(:error, nil)
     |> assign(:creating, false)
     |> assign(:execution_mode, "synchronous")}
  end

  @impl true
  def handle_event("select_variant", %{"exam_variant_id" => variant_id}, socket) do
    socket =
      case parse_id(variant_id) do
        {:ok, id} ->
          assign_selected_variant(socket, id)

        _ ->
          socket
          |> assign(:selected_variant, nil)
          |> assign(:selected_questions, [])
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_execution_mode", %{"mode" => mode}, socket)
      when mode in ["synchronous", "asynchronous"] do
    {:noreply, assign(socket, :execution_mode, mode)}
  end

  @impl true
  def handle_event("toggle_participant", %{"user-id" => user_id_str}, socket) do
    with {:ok, user_id} <- parse_id(user_id_str) do
      selected = socket.assigns.selected_ids

      new_selected =
        if MapSet.member?(selected, user_id) do
          MapSet.delete(selected, user_id)
        else
          MapSet.put(selected, user_id)
        end

      {:noreply, assign(socket, :selected_ids, new_selected)}
    else
      _ -> {:noreply, socket}
    end
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

    cond do
      Enum.empty?(user_ids) ->
        {:noreply, assign(socket, :error, "Mindestens ein Teilnehmer muss ausgewählt sein.")}

      is_nil(socket.assigns.selected_variant) ->
        {:noreply, assign(socket, :error, "Bitte wähle eine Testvariante aus.")}

      true ->
        socket = assign(socket, :creating, true)

        case Exams.create_exam(course, user_ids, user.id,
               exam_variant_id: socket.assigns.selected_variant.id,
               execution_mode: socket.assigns.execution_mode
             ) do
          {:ok, _exam} ->
            {:noreply,
             socket
             |> put_flash(:info, "Test wurde erfolgreich erstellt.")
             |> push_navigate(to: ~p"/admin/courses/#{course}/edit")}

          {:error, {:already_in_active_exam, _user_ids}} ->
            {:noreply,
             socket
             |> assign(:creating, false)
             |> assign(:error, "Einige Teilnehmer nehmen bereits an einem aktiven Test teil.")}

          {:error, reason} when is_atom(reason) ->
            {:noreply,
             socket
             |> assign(:creating, false)
             |> assign(:error, format_variant_error(reason))}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:creating, false)
             |> assign(:error, "Fehler beim Erstellen des Tests: #{inspect(reason)}")}
        end
    end
  end

  defp assign_selected_variant(socket, variant_id) do
    case Exams.load_enabled_variant_questions(variant_id, socket.assigns.course.type) do
      {:ok, variant, questions} ->
        socket
        |> assign(:selected_variant, variant)
        |> assign(:selected_questions, questions)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:selected_variant, nil)
        |> assign(:selected_questions, [])
        |> assign(:error, format_variant_error(reason))
    end
  end

  defp format_variant_error(:exam_variant_not_found), do: "Die Testvariante wurde nicht gefunden."

  defp format_variant_error(:exam_variant_not_enabled),
    do: "Diese Testvariante ist nicht aktiviert."

  defp format_variant_error(:exam_variant_course_type_mismatch) do
    "Die Testvariante passt nicht zum Kurstyp."
  end

  defp format_variant_error(:exam_variant_has_no_questions) do
    "Die Testvariante enthält keine Fragen."
  end

  defp format_variant_error(:exam_variant_has_inactive_questions) do
    "Die Testvariante enthält deaktivierte Fragen."
  end

  defp format_variant_error(:exam_variant_has_wrong_course_type_questions) do
    "Die Testvariante enthält Fragen mit falschem Kurstyp."
  end

  defp format_variant_error(:exam_variant_threshold_exceeds_max_points) do
    "Die Punktegrenzen der Testvariante überschreiten die maximal erreichbaren Punkte."
  end

  defp parse_id(id), do: WhistleWeb.ControllerHelpers.parse_id(id)

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
      <%!-- Variant selection --%>
      <div>
        <h3 class="text-sm font-semibold text-gray-700 mb-2">Testvariante</h3>
        <%= if @variants == [] do %>
          <p class="rounded-md border border-yellow-200 bg-yellow-50 px-4 py-3 text-sm text-yellow-800">
            Es gibt keine aktivierte Testvariante für diesen Kurstyp.
          </p>
        <% else %>
          <form id="exam-variant-select-form" phx-change="select_variant">
            <select
              id="exam-variant-select"
              name="exam_variant_id"
              class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
            >
              <option value="">Testvariante auswählen</option>
              <%= for variant <- @variants do %>
                <option
                  value={variant.id}
                  selected={@selected_variant && @selected_variant.id == variant.id}
                >
                  {variant.name}
                </option>
              <% end %>
            </select>
          </form>

          <div
            :if={@selected_variant}
            class="mt-3 rounded-md bg-gray-50 border border-gray-200 px-4 py-3"
          >
            <h4 class="text-sm font-semibold text-gray-700 mb-1">
              {@selected_variant.name}
            </h4>
            <p class="mt-1 text-xs text-gray-500">
              {length(@selected_questions)} Fragen ·
              Dauer: {if @execution_mode == "asynchronous",
                do: "30",
                else: div(@selected_variant.duration_seconds, 60)} Minuten
            </p>
          </div>
        <% end %>
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
          <%= if @selected_questions == [] do %>
            <p class="px-4 py-8 text-center text-sm text-gray-500">
              Wähle eine Testvariante, um die Fragen anzuzeigen.
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
