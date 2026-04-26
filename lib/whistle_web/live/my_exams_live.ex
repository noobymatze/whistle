defmodule WhistleWeb.MyExamsLive do
  use WhistleWeb, :live_view
  import Ecto.Query
  alias Whistle.Repo
  alias Whistle.Exams
  alias Whistle.Exams.{Exam, ExamParticipant, ExamQuestion}

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    exams = load_exams(user.id)

    {:ok, assign(socket, exams: exams)}
  end

  defp load_exams(user_id) do
    from(ep in ExamParticipant,
      join: e in Exam,
      on: ep.exam_id == e.id,
      join: c in Whistle.Courses.Course,
      on: c.id == e.course_id,
      where: ep.user_id == ^user_id,
      where: e.state not in ["canceled"],
      order_by: [desc: e.created_at],
      select: %{
        participant_id: ep.id,
        exam_id: e.id,
        exam_solutions_released_at: c.exam_solutions_released_at,
        course_type: e.course_type,
        state: e.state,
        started_at: e.started_at,
        exam_outcome: ep.exam_outcome,
        achieved_points: ep.achieved_points,
        max_points: ep.max_points
      }
    )
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :review, load_review(&1)))
  end

  defp load_review(%{achieved_points: nil}), do: []
  defp load_review(%{exam_solutions_released_at: nil}), do: []

  defp load_review(%{exam_id: exam_id, participant_id: participant_id}) do
    questions =
      ExamQuestion
      |> where([q], q.exam_id == ^exam_id)
      |> order_by([q], asc: q.position)
      |> Repo.all()
      |> Repo.preload(:choices)

    answers =
      participant_id
      |> Exams.list_answers_for_participant()
      |> Map.new(&{&1.exam_question_id, &1})

    Enum.map(questions, fn question ->
      answer = Map.get(answers, question.id)

      selected_choice_ids =
        if answer do
          MapSet.new(answer.answer_choices, & &1.exam_question_choice_id)
        else
          MapSet.new()
        end

      %{
        question: question,
        answer: answer,
        selected_choices:
          Enum.filter(question.choices, &MapSet.member?(selected_choice_ids, &1.id)),
        correct_choices: Enum.filter(question.choices, & &1.is_correct)
      }
    end)
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

              <%= if result = outcome_label(exam.exam_outcome) do %>
                <% {label, kind} = result %>
                <div class="text-sm mb-3">
                  <span class={
                    if kind == :pass,
                      do: "text-green-700 font-medium",
                      else: "text-red-700 font-medium"
                  }>
                    {label}
                  </span>
                  <%= if exam.achieved_points && exam.max_points do %>
                    <span class="text-zinc-500 ml-1">
                      ({exam.achieved_points}/{exam.max_points} Punkte)
                    </span>
                  <% end %>
                </div>
              <% else %>
                <%= if is_nil(exam.achieved_points) do %>
                  <p
                    id={"exam-score-pending-#{exam.exam_id}"}
                    class="mb-3 text-sm font-medium text-amber-700"
                  >
                    Dein Score ist noch nicht freigegeben.
                  </p>
                <% end %>
              <% end %>

              <%= if exam.achieved_points && is_nil(exam.exam_solutions_released_at) do %>
                <p
                  id={"exam-solutions-locked-#{exam.exam_id}"}
                  class="mt-4 border-t pt-4 text-sm text-zinc-500"
                >
                  Die Lösungen sind noch nicht freigegeben.
                </p>
              <% end %>

              <div
                :if={exam.review != []}
                id={"exam-review-#{exam.exam_id}"}
                class="mt-4 border-t pt-4"
              >
                <h5 class="mb-3 text-sm font-semibold text-zinc-800">Auswertung</h5>
                <div class="space-y-3">
                  <%= for item <- exam.review do %>
                    <div
                      id={"review-question-#{item.question.id}"}
                      class="rounded-md border border-zinc-200 bg-zinc-50 p-3 text-sm"
                    >
                      <div class="mb-2 flex items-start justify-between gap-3">
                        <p class="font-medium text-zinc-900">
                          {item.question.position}. {item.question.body_markdown}
                        </p>
                        <span class={[
                          "shrink-0 rounded-full px-2 py-0.5 text-xs font-medium",
                          item.answer && item.answer.is_correct && "bg-green-100 text-green-700",
                          (!item.answer || !item.answer.is_correct) && "bg-red-100 text-red-700"
                        ]}>
                          <%= cond do %>
                            <% item.answer == nil -> %>
                              Nicht beantwortet
                            <% item.answer.is_correct -> %>
                              Richtig
                            <% true -> %>
                              Falsch
                          <% end %>
                        </span>
                      </div>
                      <p id={"review-selected-#{item.question.id}"} class="text-zinc-600">
                        Deine Antwort: {choice_text(item.selected_choices)}
                      </p>
                      <p id={"review-correct-#{item.question.id}"} class="mt-1 text-zinc-600">
                        Richtige Antwort: {choice_text(item.correct_choices)}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>

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

  defp choice_text([]), do: "Keine Antwort"

  defp choice_text(choices) do
    choices
    |> Enum.map(& &1.body_markdown)
    |> Enum.join(", ")
  end
end
