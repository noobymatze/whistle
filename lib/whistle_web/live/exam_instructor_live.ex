defmodule WhistleWeb.ExamInstructorLive do
  use WhistleWeb, :live_view

  alias Whistle.Exams
  alias Whistle.Exams.ExamTimer
  alias Whistle.Accounts

  @presence_topic_prefix "exam_presence:"

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    exam = Exams.get_exam_with_details!(exam_id)

    if connected?(socket) do
      Exams.subscribe(exam.id)
      Phoenix.PubSub.subscribe(Whistle.PubSub, @presence_topic_prefix <> exam_id)
    end

    participants = build_participant_list(exam)

    answers_by_participant =
      if exam.state == "finished", do: Exams.list_answers_for_exam(exam.id), else: %{}

    {:ok,
     socket
     |> assign(:exam, exam)
     |> assign(:participants, participants)
     |> assign(:connected_user_ids, MapSet.new())
     |> assign(:answers_by_participant, answers_by_participant)
     |> assign(:expanded_participant_id, nil)}
  end

  @impl true
  def handle_info({:exam_state_changed, exam}, socket) do
    {:noreply, assign(socket, :exam, exam)}
  end

  @impl true
  def handle_info({:participant_connected, user_id}, socket) do
    connected = MapSet.put(socket.assigns.connected_user_ids, user_id)
    {:noreply, assign(socket, :connected_user_ids, connected)}
  end

  @impl true
  def handle_info({:participant_disconnected, user_id}, socket) do
    connected = MapSet.delete(socket.assigns.connected_user_ids, user_id)
    {:noreply, assign(socket, :connected_user_ids, connected)}
  end

  @impl true
  def handle_info({:participant_submitted, _user_id}, socket) do
    exam = Exams.get_exam_with_details!(socket.assigns.exam.id)
    participants = build_participant_list(exam)
    {:noreply, socket |> assign(:exam, exam) |> assign(:participants, participants)}
  end

  @impl true
  def handle_info({:exam_scored, exam}, socket) do
    participants = build_participant_list(exam)
    answers_by_participant = Exams.list_answers_for_exam(exam.id)

    {:noreply,
     socket
     |> assign(:exam, exam)
     |> assign(:participants, participants)
     |> assign(:answers_by_participant, answers_by_participant)}
  end

  @impl true
  def handle_event("toggle_participant_detail", %{"id" => id_str}, socket) do
    with {:ok, id} <- parse_id(id_str) do
      current = socket.assigns.expanded_participant_id
      new_id = if current == id, do: nil, else: id
      {:noreply, assign(socket, :expanded_participant_id, new_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "set_license_result",
        %{"participant_id" => participant_id, "license_result" => result},
        socket
      ) do
    with {:ok, participant_id} <- parse_id(participant_id),
         true <- result in ["L1", "L2", "L3", "fail"],
         {:ok, _participant} <- Exams.set_participant_license_result(participant_id, result) do
      exam = Exams.get_exam_with_details!(socket.assigns.exam.id)

      {:noreply,
       socket
       |> assign(:exam, exam)
       |> assign(:participants, build_participant_list(exam))
       |> put_flash(:info, "Lizenzentscheidung wurde gespeichert.")}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, "Lizenzentscheidung konnte nicht gespeichert werden.")}
    end
  end

  @impl true
  def handle_event("start", _params, socket) do
    {:ok, exam} = Exams.update_exam_state(socket.assigns.exam, "running")
    Exams.broadcast(exam.id, {:exam_state_changed, exam})

    if exam.execution_mode == "synchronous" do
      ExamTimer.start_timer(exam.id, exam.duration_seconds)
    end

    {:noreply, assign(socket, :exam, exam)}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    {:ok, exam} = Exams.update_exam_state(socket.assigns.exam, "paused")
    Exams.broadcast(exam.id, {:exam_state_changed, exam})
    {:noreply, assign(socket, :exam, exam)}
  end

  @impl true
  def handle_event("resume", _params, socket) do
    {:ok, exam} = Exams.update_exam_state(socket.assigns.exam, "running")
    Exams.broadcast(exam.id, {:exam_state_changed, exam})
    {:noreply, assign(socket, :exam, exam)}
  end

  @impl true
  def handle_event("finish", _params, socket) do
    ExamTimer.stop_timer(socket.assigns.exam.id)
    {:ok, exam} = Exams.update_exam_state(socket.assigns.exam, "finished")
    Exams.score_exam(exam)
    Exams.broadcast(exam.id, {:exam_state_changed, exam})
    {:noreply, assign(socket, :exam, exam)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    ExamTimer.stop_timer(socket.assigns.exam.id)
    {:ok, exam} = Exams.update_exam_state(socket.assigns.exam, "canceled")
    Exams.broadcast(exam.id, {:exam_state_changed, exam})
    {:noreply, assign(socket, :exam, exam)}
  end

  defp build_participant_list(exam) do
    user_ids = Enum.map(exam.participants, & &1.user_id)

    users =
      user_ids
      |> Enum.map(&Accounts.get_user!/1)
      |> Map.new(fn u -> {u.id, u} end)

    Enum.map(exam.participants, fn p ->
      user = Map.get(users, p.user_id)
      %{participant: p, user: user}
    end)
    |> Enum.sort_by(fn %{user: u} ->
      if u, do: "#{u.last_name} #{u.first_name}", else: ""
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.header>
        Test – {@exam.course_type}
        <:subtitle>
          Typ: {@exam.course_type} · {@exam.question_count} Fragen · {div(@exam.duration_seconds, 60)} Minuten · {execution_mode_label(
            @exam.execution_mode
          )} ·
          <span class={[
            "inline-flex rounded-full px-2 py-0.5 text-xs font-medium",
            @exam.state == "waiting_room" && "bg-yellow-100 text-yellow-800",
            @exam.state == "running" && "bg-green-100 text-green-800",
            @exam.state == "paused" && "bg-orange-100 text-orange-800",
            @exam.state == "finished" && "bg-gray-100 text-gray-600",
            @exam.state == "canceled" && "bg-red-100 text-red-700"
          ]}>
            {state_label(@exam.state)}
          </span>
        </:subtitle>
      </.header>

      <%!-- Controls --%>
      <div class="mt-6 mb-8 flex flex-wrap gap-3">
        <%= if @exam.state == "waiting_room" do %>
          <.button phx-click="start">▶ Starten</.button>
          <.button phx-click="cancel" data-confirm="Test wirklich abbrechen?">Abbrechen</.button>
        <% end %>
        <%= if @exam.state == "running" do %>
          <.button phx-click="pause">⏸ Pausieren</.button>
          <.button phx-click="finish" data-confirm="Test jetzt beenden?">⏹ Beenden</.button>
          <.button phx-click="cancel" data-confirm="Test wirklich abbrechen?">Abbrechen</.button>
        <% end %>
        <%= if @exam.state == "paused" do %>
          <.button phx-click="resume">▶ Fortsetzen</.button>
          <.button phx-click="finish" data-confirm="Test jetzt beenden?">⏹ Beenden</.button>
          <.button phx-click="cancel" data-confirm="Test wirklich abbrechen?">Abbrechen</.button>
        <% end %>
      </div>

      <%!-- Participant list --%>
      <div>
        <h2 class="text-base font-semibold text-gray-900 mb-3">
          Teilnehmende
          <span class="font-normal text-gray-500 text-sm">
            ({MapSet.size(@connected_user_ids)} verbunden · {length(@participants)} gesamt)
          </span>
        </h2>
        <div class="divide-y divide-gray-100 border border-gray-200 rounded-md overflow-hidden">
          <%= for %{participant: p, user: u} <- @participants do %>
            <div id={"participant-#{p.user_id}"}>
              <div class="flex items-center justify-between px-4 py-3 text-sm gap-3">
                <div class="flex items-center gap-3 min-w-0">
                  <span class={[
                    "inline-block w-2 h-2 rounded-full flex-shrink-0",
                    MapSet.member?(@connected_user_ids, p.user_id) && "bg-green-500",
                    !MapSet.member?(@connected_user_ids, p.user_id) && "bg-gray-300"
                  ]} />
                  <span class="font-medium truncate">
                    {if u, do: "#{u.first_name} #{u.last_name}", else: "Benutzer ##{p.user_id}"}
                  </span>
                </div>
                <div class="flex items-center gap-2 flex-shrink-0">
                  <span
                    id={"participant-state-#{p.user_id}"}
                    class={[
                      "text-xs px-2 py-0.5 rounded-full",
                      p.state == "waiting" && "bg-gray-100 text-gray-500",
                      p.state == "running" && "bg-blue-100 text-blue-700",
                      p.state == "submitted" && "bg-green-100 text-green-700",
                      p.state == "timed_out" && "bg-red-100 text-red-600",
                      p.state == "disconnected" && "bg-orange-100 text-orange-600"
                    ]}
                  >
                    {participant_state_label(p.state)}
                  </span>
                  <%= if p.achieved_points != nil do %>
                    <span
                      id={"participant-points-#{p.user_id}"}
                      class="text-xs text-gray-600"
                    >
                      {p.achieved_points} / {p.max_points} Pkt.
                    </span>
                  <% end %>
                  <form
                    id={"license-result-form-#{p.id}"}
                    phx-change="set_license_result"
                    class="flex items-center gap-1 rounded-md border border-gray-200 bg-white p-1"
                  >
                    <input type="hidden" name="participant_id" value={p.id} />
                    <%= for {label, value} <- [{"L1", "L1"}, {"L2", "L2"}, {"L3", "L3"}, {"Nicht bestanden", "fail"}] do %>
                      <label
                        id={"license-result-#{p.id}-#{value}"}
                        class={[
                          "cursor-pointer rounded px-2 py-0.5 text-xs font-medium transition-colors",
                          participant_license_result(p) == value && value == "fail" &&
                            "bg-red-100 text-red-700",
                          participant_license_result(p) == value && value != "fail" &&
                            "bg-blue-100 text-blue-700",
                          participant_license_result(p) != value &&
                            "text-gray-500 hover:bg-gray-50"
                        ]}
                      >
                        <input
                          type="radio"
                          name="license_result"
                          value={value}
                          checked={participant_license_result(p) == value}
                          class="sr-only"
                        />
                        {label}
                      </label>
                    <% end %>
                  </form>
                  <%= if Map.has_key?(@answers_by_participant, p.id) do %>
                    <button
                      type="button"
                      phx-click="toggle_participant_detail"
                      phx-value-id={p.id}
                      class="text-xs px-2 py-0.5 rounded border border-gray-300 text-gray-500 hover:bg-gray-50"
                    >
                      {if @expanded_participant_id == p.id, do: "▲ Details", else: "▼ Details"}
                    </button>
                  <% end %>
                </div>
              </div>

              <%= if @expanded_participant_id == p.id do %>
                <% answers = Map.get(@answers_by_participant, p.id, []) %>
                <div class="px-4 pb-3 bg-gray-50 border-t border-gray-100">
                  <table class="w-full text-xs mt-2">
                    <thead>
                      <tr class="text-gray-500 text-left">
                        <th class="py-1 pr-2 font-medium w-8">#</th>
                        <th class="py-1 pr-2 font-medium">Frage</th>
                        <th class="py-1 pr-2 font-medium">Schwierigkeit</th>
                        <th class="py-1 pr-2 font-medium">Punkte</th>
                        <th class="py-1 font-medium">Ergebnis</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-100">
                      <%= for question <- @exam.questions do %>
                        <% answer = Enum.find(answers, &(&1.exam_question_id == question.id)) %>
                        <tr>
                          <td class="py-1 pr-2 text-gray-400">{question.position}</td>
                          <td
                            class="py-1 pr-2 text-gray-700 max-w-xs truncate"
                            title={question.body_markdown}
                          >
                            {question.body_markdown}
                          </td>
                          <td class="py-1 pr-2">
                            <span class={[
                              "inline-flex items-center rounded-full px-1.5 py-0.5 font-medium",
                              question.difficulty == "low" && "bg-green-100 text-green-700",
                              question.difficulty == "medium" && "bg-yellow-100 text-yellow-700",
                              question.difficulty == "high" && "bg-red-100 text-red-700"
                            ]}>
                              {case question.difficulty do
                                "low" -> "Leicht"
                                "medium" -> "Mittel"
                                "high" -> "Schwer"
                                d -> d
                              end}
                            </span>
                          </td>
                          <td class="py-1 pr-2 text-gray-600">
                            {if answer,
                              do: "#{answer.awarded_points}/#{question.points}",
                              else: "–/#{question.points}"}
                          </td>
                          <td class="py-1">
                            <%= cond do %>
                              <% answer == nil -> %>
                                <span class="text-gray-400">Nicht beantwortet</span>
                              <% answer.is_correct -> %>
                                <span class="text-green-700 font-medium">✓ Richtig</span>
                              <% true -> %>
                                <span class="text-red-600 font-medium">✗ Falsch</span>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp state_label("waiting_room"), do: "Warteraum"
  defp state_label("running"), do: "Läuft"
  defp state_label("paused"), do: "Pausiert"
  defp state_label("finished"), do: "Beendet"
  defp state_label("canceled"), do: "Abgebrochen"
  defp state_label(s), do: s

  defp participant_state_label("waiting"), do: "Wartet"
  defp participant_state_label("running"), do: "Aktiv"
  defp participant_state_label("submitted"), do: "Abgegeben"
  defp participant_state_label("timed_out"), do: "Zeit abgelaufen"
  defp participant_state_label("disconnected"), do: "Getrennt"
  defp participant_state_label("paused"), do: "Pausiert"
  defp participant_state_label(s), do: s

  defp execution_mode_label("synchronous"), do: "Synchron"
  defp execution_mode_label("asynchronous"), do: "Asynchron"
  defp execution_mode_label(m), do: m

  defp participant_license_result(%{exam_outcome: "l1_pass"}), do: "L1"
  defp participant_license_result(%{exam_outcome: "l1_eligible"}), do: "L1"
  defp participant_license_result(%{exam_outcome: "l2_pass"}), do: "L2"
  defp participant_license_result(%{exam_outcome: "l3_pass"}), do: "L3"
  defp participant_license_result(%{exam_outcome: "fail"}), do: "fail"
  defp participant_license_result(_participant), do: nil

  defp parse_id(id), do: WhistleWeb.ControllerHelpers.parse_id(id)
end
