defmodule WhistleWeb.ExamParticipantLive do
  use WhistleWeb, :live_view

  on_mount WhistleWeb.UserAuthLive

  alias Whistle.Exams

  @presence_topic_prefix "exam_presence:"

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    user = socket.assigns.current_user
    exam = Exams.get_exam!(exam_id)

    participant = Exams.get_exam_participant(exam.id, user.id)

    unless participant do
      {:ok,
       socket
       |> put_flash(:error, "Du bist nicht für diesen Exam angemeldet.")
       |> push_navigate(to: ~p"/")}
    else
      if connected?(socket) do
        Exams.subscribe(exam.id)
        Exams.update_participant_state(participant, "connected")

        Phoenix.PubSub.broadcast(
          Whistle.PubSub,
          @presence_topic_prefix <> exam_id,
          {:participant_connected, user.id}
        )
      end

      {questions, answers_map} =
        if exam.state in ["running", "paused", "finished"] do
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

      {:ok,
       socket
       |> assign(:exam, exam)
       |> assign(:participant, participant)
       |> assign(:questions, questions)
       |> assign(:answers_map, answers_map)
       |> assign(:current_index, 0)
       |> assign(:submitted, participant.state == "submitted")}
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
      if exam.state in ["running", "paused"] && Enum.empty?(socket.assigns.questions) do
        questions = load_exam_questions(exam.id)
        assign(socket, :questions, questions)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_choice", %{"question-id" => qid_str, "choice-id" => cid_str}, socket) do
    if socket.assigns.exam.state != "running" || socket.assigns.submitted do
      {:noreply, socket}
    else
      qid = String.to_integer(qid_str)
      cid = String.to_integer(cid_str)
      question = Enum.find(socket.assigns.questions, &(&1.id == qid))
      participant = socket.assigns.participant

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
  def handle_event("submit", _params, socket) do
    if socket.assigns.submitted || socket.assigns.exam.state != "running" do
      {:noreply, socket}
    else
      {:ok, participant} =
        Exams.update_participant_state(socket.assigns.participant, "submitted")

      Exams.broadcast(socket.assigns.exam.id, {:participant_submitted, participant.user_id})

      {:noreply,
       socket
       |> assign(:participant, participant)
       |> assign(:submitted, true)}
    end
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
          <%= if @submitted do %>
            <.submitted_screen participant={@participant} />
          <% else %>
            <.question_screen
              exam={@exam}
              questions={@questions}
              answers_map={@answers_map}
              current_index={@current_index}
            />
          <% end %>
      <% end %>
    </div>
    """
  end

  defp waiting_room(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <div class="mb-8">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-100 mb-4">
          <span class="text-2xl">📋</span>
        </div>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">{@exam.title}</h1>
        <p class="text-gray-600 text-lg">Der Test startet in wenigen Minuten.</p>
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
    <div class={[
      "mt-4 w-full max-w-sm rounded-xl border-2 p-6",
      @participant.passed && "border-green-400 bg-green-50",
      !@participant.passed && "border-red-300 bg-red-50"
    ]}>
      <p class={[
        "text-2xl font-bold mb-1",
        @participant.passed && "text-green-700",
        !@participant.passed && "text-red-600"
      ]}>
        <%= if @participant.passed do %>
          Bestanden
        <% else %>
          Nicht bestanden
        <% end %>
      </p>
      <p class="text-lg text-gray-700 mb-1">
        {@participant.score} / {@participant.max_score} Punkte
      </p>
      <%= if @participant.passed do %>
        <p class="mt-3 text-sm text-gray-600">
          Eine vorläufige Lizenz wurde ausgestellt.
        </p>
      <% end %>
    </div>
    """
  end

  attr :exam, :map, required: true
  attr :questions, :list, required: true
  attr :answers_map, :map, required: true
  attr :current_index, :integer, required: true

  defp question_screen(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen max-w-lg mx-auto px-4 py-6">
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
                  "w-full text-left rounded-xl border-2 px-4 py-3 text-sm transition-colors",
                  selected && "border-blue-500 bg-blue-50 text-blue-900",
                  !selected &&
                    "border-gray-200 bg-white text-gray-800 hover:border-gray-300 active:bg-gray-50"
                ]}
              >
                {render_markdown(choice.body_markdown)}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Navigation --%>
        <div class="mt-6 flex items-center justify-between gap-3">
          <button
            phx-click="prev"
            disabled={@current_index == 0}
            class="flex-1 rounded-lg border border-gray-300 px-4 py-3 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            ← Zurück
          </button>

          <%= if @current_index < length(@questions) - 1 do %>
            <button
              phx-click="next"
              class="flex-1 rounded-lg bg-blue-600 px-4 py-3 text-sm font-semibold text-white hover:bg-blue-500"
            >
              Weiter →
            </button>
          <% else %>
            <button
              phx-click="submit"
              data-confirm="Test jetzt abgeben?"
              class="flex-1 rounded-lg bg-green-600 px-4 py-3 text-sm font-semibold text-white hover:bg-green-500"
            >
              Abgeben ✓
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
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
