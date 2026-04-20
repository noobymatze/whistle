defmodule WhistleWeb.ExamInstructorLive do
  use WhistleWeb, :live_view

  on_mount WhistleWeb.UserAuthLive

  alias Whistle.Exams
  alias Whistle.Exams.ExamTimer
  alias Whistle.Accounts
  alias Whistle.Accounts.Role

  @presence_topic_prefix "exam_presence:"

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    user = socket.assigns.current_user

    unless Role.can_access_course_area?(user) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      exam = Exams.get_exam_with_details!(exam_id)

      if connected?(socket) do
        Exams.subscribe(exam.id)
        Phoenix.PubSub.subscribe(Whistle.PubSub, @presence_topic_prefix <> exam_id)
      end

      participants = build_participant_list(exam)

      {:ok,
       socket
       |> assign(:exam, exam)
       |> assign(:participants, participants)
       |> assign(:connected_user_ids, MapSet.new())}
    end
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
    {:noreply, socket |> assign(:exam, exam) |> assign(:participants, participants)}
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
          Typ: {@exam.course_type} · {@exam.question_count} Fragen · {div(@exam.duration_seconds, 60)} Minuten ·
          {execution_mode_label(@exam.execution_mode)} ·
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
            <div id={"participant-#{p.user_id}"} class="flex items-center justify-between px-4 py-3 text-sm gap-3">
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
                <%= if p.exam_outcome != nil do %>
                  <span
                    id={"participant-outcome-#{p.user_id}"}
                    class={[
                      "text-xs px-2 py-0.5 rounded-full font-medium",
                      p.exam_outcome == "l3_pass" && "bg-green-100 text-green-700",
                      p.exam_outcome == "l2_pass" && "bg-blue-100 text-blue-700",
                      p.exam_outcome == "l1_eligible" && "bg-purple-100 text-purple-700",
                      p.exam_outcome == "fail" && "bg-red-100 text-red-600",
                      p.exam_outcome == "not_applicable" && "bg-gray-100 text-gray-500"
                    ]}
                  >
                    {exam_outcome_label(p.exam_outcome)}
                  </span>
                <% end %>
                <%= if p.l1_review_eligible do %>
                  <span
                    id={"l1-review-badge-#{p.user_id}"}
                    class="text-xs px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 font-medium"
                  >
                    L1-Prüfung erforderlich
                  </span>
                <% end %>
              </div>
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

  defp exam_outcome_label("l3_pass"), do: "L3"
  defp exam_outcome_label("l2_pass"), do: "L2"
  defp exam_outcome_label("l1_eligible"), do: "L2 + L1-Prüfung"
  defp exam_outcome_label("fail"), do: "Nicht bestanden"
  defp exam_outcome_label("not_applicable"), do: "–"
  defp exam_outcome_label(o), do: o
end
