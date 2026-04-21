defmodule WhistleWeb.ExamParticipantLive do
  use WhistleWeb, :live_view

  on_mount WhistleWeb.UserAuthLive

  alias Whistle.Exams

  @presence_topic_prefix "exam_presence:"
  @tick_interval_ms 1_000

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    user = socket.assigns.current_user
    exam = Exams.get_exam!(exam_id)

    participant = Exams.get_exam_participant(exam.id, user.id)

    unless participant do
      {:ok,
       socket
       |> put_flash(:error, "Du bist nicht für diesen Test angemeldet.")
       |> push_navigate(to: ~p"/")}
    else
      if connected?(socket) do
        Exams.subscribe(exam.id)

        if exam.execution_mode == "synchronous" do
          Exams.update_participant_state(participant, "connected")
        end

        Phoenix.PubSub.broadcast(
          Whistle.PubSub,
          @presence_topic_prefix <> exam_id,
          {:participant_connected, user.id}
        )
      end

      {participant, already_submitted} =
        maybe_auto_submit_on_mount(exam, participant)

      already_submitted = already_submitted || participant.state in ["submitted", "timed_out"]

      {questions, answers_map} = maybe_load_questions(exam, participant)

      socket =
        socket
        |> assign(:exam, exam)
        |> assign(:participant, participant)
        |> assign(:questions, questions)
        |> assign(:answers_map, answers_map)
        |> assign(:current_index, 0)
        |> assign(:submitted, already_submitted)
        |> assign(:remaining_seconds, compute_remaining_seconds(exam, participant))

      socket = maybe_schedule_tick(socket, exam, participant)

      {:ok, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if user = socket.assigns[:current_user] do
      exam = socket.assigns[:exam]

      if exam && socket.assigns[:participant] do
        participant = socket.assigns.participant
        Exams.update_participant_state(participant, "disconnected")

        Phoenix.PubSub.broadcast(
          Whistle.PubSub,
          @presence_topic_prefix <> to_string(exam.id),
          {:participant_disconnected, user.id}
        )
      end
    end

    :ok
  end

  @impl true
  def handle_info({:exam_scored, _exam}, socket) do
    participant =
      Exams.get_exam_participant(socket.assigns.exam.id, socket.assigns.current_user.id)

    {:noreply, assign(socket, :participant, participant)}
  end

  @impl true
  def handle_info({:participant_submitted, _user_id}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:participant_connected, _user_id}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:participant_disconnected, _user_id}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:exam_state_changed, exam}, socket) do
    socket = assign(socket, :exam, exam)

    socket =
      if exam.state in ["running", "paused"] && Enum.empty?(socket.assigns.questions) &&
           exam.execution_mode == "synchronous" do
        questions = load_exam_questions(exam.id)
        assign(socket, :questions, questions)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    exam = socket.assigns.exam
    participant = socket.assigns.participant

    if Exams.async_deadline_passed?(participant) && !socket.assigns.submitted do
      {:ok, updated} = Exams.update_participant_state(participant, "submitted")

      Exams.broadcast(exam.id, {:participant_submitted, updated.user_id})
      Exams.score_exam(exam)

      {:noreply,
       socket
       |> assign(
         :participant,
         Exams.get_exam_participant(exam.id, socket.assigns.current_user.id)
       )
       |> assign(:submitted, true)
       |> assign(:remaining_seconds, 0)}
    else
      remaining = compute_remaining_seconds(exam, participant)
      Process.send_after(self(), :tick, @tick_interval_ms)
      {:noreply, assign(socket, :remaining_seconds, remaining)}
    end
  end

  @impl true
  def handle_event("start_async", _params, socket) do
    exam = socket.assigns.exam
    participant = socket.assigns.participant

    if exam.execution_mode != "asynchronous" || exam.state != "running" do
      {:noreply, socket}
    else
      case Exams.start_async_participant(participant) do
        {:ok, updated_participant} ->
          questions = load_exam_questions(exam.id)
          Process.send_after(self(), :tick, @tick_interval_ms)

          {:noreply,
           socket
           |> assign(:participant, updated_participant)
           |> assign(:questions, questions)
           |> assign(:remaining_seconds, compute_remaining_seconds(exam, updated_participant))}

        {:error, :already_started} ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("select_choice", %{"question-id" => qid_str, "choice-id" => cid_str}, socket) do
    exam = socket.assigns.exam
    participant = socket.assigns.participant

    can_answer =
      exam.state == "running" &&
        !socket.assigns.submitted &&
        (exam.execution_mode == "synchronous" || participant.async_started_at != nil) &&
        !Exams.async_deadline_passed?(participant)

    if !can_answer do
      {:noreply, socket}
    else
      qid = String.to_integer(qid_str)
      cid = String.to_integer(cid_str)
      question = Enum.find(socket.assigns.questions, &(&1.id == qid))

      new_answers_map =
        if question.type == "single_choice" do
          Map.put(socket.assigns.answers_map, qid, MapSet.new([cid]))
        else
          current = Map.get(socket.assigns.answers_map, qid, MapSet.new())

          updated =
            if MapSet.member?(current, cid) do
              MapSet.delete(current, cid)
            else
              MapSet.put(current, cid)
            end

          Map.put(socket.assigns.answers_map, qid, updated)
        end

      choice_ids = MapSet.to_list(Map.get(new_answers_map, qid, MapSet.new()))
      Exams.upsert_answer(participant, question, choice_ids)

      {:noreply, assign(socket, :answers_map, new_answers_map)}
    end
  end

  @impl true
  def handle_event("prev", _params, socket) do
    idx = max(0, socket.assigns.current_index - 1)
    {:noreply, assign(socket, :current_index, idx)}
  end

  @impl true
  def handle_event("next", _params, socket) do
    idx = min(length(socket.assigns.questions) - 1, socket.assigns.current_index + 1)
    {:noreply, assign(socket, :current_index, idx)}
  end

  @impl true
  def handle_event("goto", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    max_idx = length(socket.assigns.questions) - 1
    {:noreply, assign(socket, :current_index, max(0, min(idx, max_idx)))}
  end

  @impl true
  def handle_event("cancel_attempt", _params, socket) do
    exam = socket.assigns.exam
    participant = socket.assigns.participant

    if exam.execution_mode != "asynchronous" || socket.assigns.submitted do
      {:noreply, socket}
    else
      {:ok, updated} = Exams.cancel_async_participant(participant)
      Exams.broadcast(exam.id, {:participant_submitted, updated.user_id})

      {:noreply,
       socket
       |> assign(:participant, updated)
       |> assign(:submitted, true)}
    end
  end

  @impl true
  def handle_event("submit", _params, socket) do
    exam = socket.assigns.exam
    participant = socket.assigns.participant

    if socket.assigns.submitted || exam.state != "running" do
      {:noreply, socket}
    else
      if Exams.async_deadline_passed?(participant) do
        {:noreply, socket}
      else
        {:ok, updated} = Exams.update_participant_state(participant, "submitted")

        Exams.broadcast(exam.id, {:participant_submitted, updated.user_id})

        {:noreply,
         socket
         |> assign(:participant, updated)
         |> assign(:submitted, true)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= case @exam.state do %>
        <% "waiting_room" -> %>
          <.waiting_room exam={@exam} />
        <% "paused" -> %>
          <.paused_screen exam={@exam} />
        <% "finished" -> %>
          <.finished_screen submitted={@submitted} participant={@participant} />
        <% "canceled" -> %>
          <.canceled_screen />
        <% _ -> %>
          <%= cond do %>
            <% @submitted -> %>
              <.submitted_screen participant={@participant} />
            <% @exam.execution_mode == "asynchronous" && @participant.async_started_at == nil -> %>
              <.async_prestart_screen exam={@exam} />
            <% true -> %>
              <.question_screen
                exam={@exam}
                questions={@questions}
                answers_map={@answers_map}
                current_index={@current_index}
                remaining_seconds={@remaining_seconds}
                async={@exam.execution_mode == "asynchronous"}
              />
          <% end %>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Screen components
  # ---------------------------------------------------------------------------

  defp waiting_room(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <div class="mb-8">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-100 mb-4">
          <span class="text-2xl">📋</span>
        </div>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Prüfung</h1>
        <p class="text-gray-600 text-lg">
          <%= if @exam.execution_mode == "asynchronous" do %>
            Du kannst den Test starten, sobald er freigeschaltet wird.
          <% else %>
            Der Test startet in wenigen Minuten.
          <% end %>
        </p>
      </div>
      <div class="flex items-center gap-2 text-gray-500 text-sm">
        <svg
          class="animate-spin h-4 w-4"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
          </circle>
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
          >
          </path>
        </svg>
        Bitte Seite offen lassen
      </div>
    </div>
    """
  end

  attr :exam, :map, required: true

  defp async_prestart_screen(assigns) do
    ~H"""
    <div
      id="async-prestart"
      class="flex flex-col items-center justify-center min-h-screen px-6 text-center"
    >
      <div class="mb-8">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-100 mb-4">
          <span class="text-2xl">⏱</span>
        </div>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Test bereit</h1>
        <p class="text-gray-600 text-lg mb-2">
          Du hast <strong>30 Minuten</strong> Zeit, sobald du den Test gestartet hast.
        </p>
        <p class="text-gray-500 text-sm">
          Der Timer startet erst, wenn du auf „Test starten" klickst. Lies dir die Hinweise gut durch.
        </p>
      </div>
      <.button
        id="start-async-btn"
        phx-click="start_async"
        data-confirm="Bist du sicher? Der 30-Minuten-Timer startet sofort."
      >
        Test starten →
      </.button>
    </div>
    """
  end

  defp paused_screen(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-orange-100 mb-4">
        <span class="text-2xl">⏸</span>
      </div>
      <h2 class="text-xl font-bold text-gray-900 mb-2">Test pausiert</h2>
      <p class="text-gray-500">Bitte warte auf den Instructor.</p>
    </div>
    """
  end

  defp finished_screen(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-gray-100 mb-4">
        <span class="text-2xl">🏁</span>
      </div>
      <h2 class="text-xl font-bold text-gray-900 mb-2">Test beendet</h2>
      <%= if @participant.score != nil do %>
        <.result_card participant={@participant} />
      <% else %>
        <p class="text-gray-500">
          <%= if @submitted do %>
            Deine Antworten wurden gespeichert. Das Ergebnis wird in Kürze berechnet.
          <% else %>
            Der Test wurde vom Instructor beendet.
          <% end %>
        </p>
      <% end %>
    </div>
    """
  end

  defp canceled_screen(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <h2 class="text-xl font-bold text-gray-900 mb-2">Test abgebrochen</h2>
      <p class="text-gray-500">Dieser Test wurde abgebrochen.</p>
    </div>
    """
  end

  defp submitted_screen(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-green-100 mb-4">
        <span class="text-2xl">✓</span>
      </div>
      <h2 class="text-xl font-bold text-gray-900 mb-2">Abgegeben</h2>
      <%= if @participant.score != nil do %>
        <.result_card participant={@participant} />
      <% else %>
        <p class="text-gray-500">
          Deine Antworten wurden erfolgreich übermittelt. Das Ergebnis wird in Kürze berechnet.
        </p>
      <% end %>
    </div>
    """
  end

  attr :participant, :map, required: true

  defp result_card(assigns) do
    ~H"""
    <div class="mt-4 w-full max-w-sm rounded-xl border-2 border-gray-200 bg-gray-50 p-6">
      <p class="text-2xl font-bold text-gray-800 mb-1">
        {@participant.achieved_points || @participant.score} / {@participant.max_points ||
          @participant.max_score} Punkte
      </p>
    </div>
    """
  end

  attr :exam, :map, required: true
  attr :questions, :list, required: true
  attr :answers_map, :map, required: true
  attr :current_index, :integer, required: true
  attr :remaining_seconds, :integer, default: nil
  attr :async, :boolean, default: false

  defp question_screen(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen max-w-lg mx-auto px-4 py-6">
      <%!-- Timer (shown for async exams or when show_countdown_to_participants is enabled) --%>
      <%= if @remaining_seconds != nil && (@exam.execution_mode == "asynchronous" || @exam.show_countdown_to_participants) do %>
        <div id="countdown" class="mb-3 text-right text-sm font-mono text-gray-600">
          {format_countdown(@remaining_seconds)}
        </div>
      <% end %>

      <%!-- Progress bar --%>
      <div class="mb-4">
        <div class="flex justify-between text-xs text-gray-500 mb-1">
          <span>Frage {@current_index + 1} von {length(@questions)}</span>
          <span>
            {Enum.count(@answers_map)} beantwortet
          </span>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-1.5">
          <div
            class="bg-blue-500 h-1.5 rounded-full transition-all"
            style={"width: #{trunc((@current_index + 1) / max(length(@questions), 1) * 100)}%"}
          />
        </div>
      </div>

      <%!-- Question mini-nav --%>
      <div class="flex flex-wrap gap-1 mb-4">
        <%= for {_q, i} <- Enum.with_index(@questions) do %>
          <button
            type="button"
            phx-click="goto"
            phx-value-index={i}
            class={[
              "w-7 h-7 rounded text-xs font-medium",
              i == @current_index && "bg-blue-600 text-white",
              i != @current_index && Map.has_key?(@answers_map, Enum.at(@questions, i).id) &&
                "bg-green-100 text-green-700",
              i != @current_index && !Map.has_key?(@answers_map, Enum.at(@questions, i).id) &&
                "bg-gray-100 text-gray-600"
            ]}
          >
            {i + 1}
          </button>
        <% end %>
      </div>

      <%!-- Current question --%>
      <%= if current_q = Enum.at(@questions, @current_index) do %>
        <div class="flex-1">
          <div class="mb-6 text-base leading-relaxed text-gray-900 font-medium">
            {render_markdown(current_q.body_markdown)}
          </div>

          <%!-- Choices --%>
          <div class="mb-3 text-xs text-gray-500 font-medium">
            <%= if current_q.type == "multiple_choice" do %>
              Mehrere Antworten möglich
            <% else %>
              Eine Antwort auswählen
            <% end %>
          </div>
          <div class="space-y-3">
            <%= for choice <- current_q.choices do %>
              <% selected =
                MapSet.member?(Map.get(@answers_map, current_q.id, MapSet.new()), choice.id) %>
              <button
                type="button"
                phx-click="select_choice"
                phx-value-question-id={current_q.id}
                phx-value-choice-id={choice.id}
                class={[
                  "w-full text-left rounded-xl border-2 px-4 py-3 text-sm transition-colors flex items-start gap-3",
                  selected && "border-blue-500 bg-blue-50 text-blue-900",
                  !selected &&
                    "border-gray-200 bg-white text-gray-800 hover:border-gray-300 active:bg-gray-50"
                ]}
              >
                <span class={[
                  "mt-0.5 flex-shrink-0 flex items-center justify-center text-xs font-bold",
                  current_q.type == "multiple_choice" && selected &&
                    "w-4 h-4 rounded border-2 border-blue-500 bg-blue-500 text-white",
                  current_q.type == "multiple_choice" && !selected &&
                    "w-4 h-4 rounded border-2 border-gray-400 bg-white",
                  current_q.type == "single_choice" && selected &&
                    "w-4 h-4 rounded-full border-2 border-blue-500 bg-blue-500 text-white",
                  current_q.type == "single_choice" && !selected &&
                    "w-4 h-4 rounded-full border-2 border-gray-400 bg-white"
                ]}>
                  <%= if selected && current_q.type == "multiple_choice" do %>✓<% end %>
                </span>
                <span>{render_markdown(choice.body_markdown)}</span>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Navigation --%>
        <div class="mt-6 flex items-center justify-between gap-3">
          <.button phx-click="prev" disabled={@current_index == 0} class="flex-1 py-3">
            ← Zurück
          </.button>

          <%= if @current_index < length(@questions) - 1 do %>
            <.button phx-click="next" class="flex-1 py-3">Weiter →</.button>
          <% else %>
            <.button phx-click="submit" data-confirm="Test jetzt abgeben?" class="flex-1 py-3">
              Abgeben ✓
            </.button>
          <% end %>
        </div>

        <%= if @async do %>
          <div class="mt-4 text-center">
            <.button
              phx-click="cancel_attempt"
              data-confirm="Test wirklich abbrechen? Dein Versuch wird als nicht bestanden gewertet."
            >
              Test abbrechen
            </.button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp maybe_load_questions(exam, participant) do
    should_load =
      exam.state in ["running", "paused", "finished"] &&
        (exam.execution_mode == "synchronous" || participant.async_started_at != nil)

    if should_load do
      questions = load_exam_questions(exam.id)
      answers = Exams.list_answers_for_participant(participant.id)

      answers_map =
        Map.new(answers, fn a ->
          choice_ids = MapSet.new(a.answer_choices, & &1.exam_question_choice_id)
          {a.exam_question_id, choice_ids}
        end)

      {questions, answers_map}
    else
      {[], %{}}
    end
  end

  defp maybe_schedule_tick(socket, exam, participant) do
    needs_tick =
      exam.execution_mode == "asynchronous" &&
        participant.async_started_at != nil &&
        participant.state not in ["submitted", "timed_out"] &&
        !Exams.async_deadline_passed?(participant)

    if needs_tick do
      Process.send_after(self(), :tick, @tick_interval_ms)
    end

    socket
  end

  defp maybe_auto_submit_on_mount(exam, participant) do
    deadline_passed = Exams.async_deadline_passed?(participant)
    not_yet_submitted = participant.state not in ["submitted", "timed_out"]

    if exam.execution_mode == "asynchronous" && deadline_passed && not_yet_submitted do
      {:ok, updated} = Exams.update_participant_state(participant, "submitted")
      Exams.broadcast(exam.id, {:participant_submitted, updated.user_id})
      Exams.score_exam(exam)
      fresh = Exams.get_exam_participant(exam.id, participant.user_id)
      {fresh, true}
    else
      {participant, false}
    end
  end

  defp compute_remaining_seconds(_exam, %{async_deadline_at: nil}), do: nil

  defp compute_remaining_seconds(_exam, %{async_deadline_at: deadline}) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(deadline, now, :second)
    max(0, diff)
  end

  defp format_countdown(seconds) when seconds <= 0, do: "00:00"

  defp format_countdown(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [m, s]) |> IO.iodata_to_binary()
  end

  defp load_exam_questions(exam_id) do
    import Ecto.Query
    alias Whistle.Repo

    Whistle.Exams.ExamQuestion
    |> where([q], q.exam_id == ^exam_id)
    |> order_by([q], asc: q.position)
    |> Repo.all()
    |> Repo.preload(choices: from(c in Whistle.Exams.ExamQuestionChoice, order_by: c.position))
  end

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(markdown) do
    case Earmark.as_html(markdown, escape: false) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      {:error, _, _} -> Phoenix.HTML.raw(Phoenix.HTML.html_escape(markdown))
    end
  end
end
