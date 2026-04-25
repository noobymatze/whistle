defmodule WhistleWeb.ExamVariantLive do
  use WhistleWeb, :live_view

  alias Whistle.Exams
  alias Whistle.Exams.ExamVariant
  alias Whistle.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:course_types, ExamVariant.valid_course_types())
     |> assign(:statuses, ExamVariant.valid_statuses())
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{live_action: :index}} = socket) do
    course_type = params["course_type"] || ""
    status = params["status"] || ""

    variants =
      []
      |> maybe_put(:course_type, course_type)
      |> maybe_put(:status, status)
      |> Exams.list_exam_variants()
      |> Repo.preload(:variant_questions)

    {:noreply,
     socket
     |> assign(:page_title, "Testvarianten")
     |> assign(:variants, variants)
     |> assign(:filter_course_type, course_type)
     |> assign(:filter_status, status)}
  end

  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    variant = %ExamVariant{
      course_type: "F",
      status: "draft",
      duration_seconds: 30 * 60
    }

    changeset = Exams.change_exam_variant(variant)

    {:noreply,
     socket
     |> assign(:page_title, "Neue Testvariante")
     |> assign_form_state(nil, changeset, %{})}
  end

  def handle_params(%{"id" => id}, _uri, %{assigns: %{live_action: :edit}} = socket) do
    with {:ok, id} <- parse_id(id),
         %ExamVariant{} = variant <- Repo.get(ExamVariant, id) do
      changeset = Exams.change_exam_variant(variant)
      selected_positions = selected_positions_for(variant)

      {:noreply,
       socket
       |> assign(:page_title, "Testvariante bearbeiten")
       |> assign_form_state(variant, changeset, selected_positions)}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Testvariante wurde nicht gefunden.")
         |> push_navigate(to: ~p"/admin/exam-variants")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      params
      |> Map.take(["course_type", "status"])
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/admin/exam-variants?#{query}")}
  end

  def handle_event("validate", %{"exam_variant" => variant_params} = params, socket) do
    variant = socket.assigns.variant || %ExamVariant{}
    question_positions = parse_question_positions(params["variant_questions"] || %{})
    selected_positions = Map.new(question_positions)

    changeset =
      variant
      |> Exams.change_exam_variant(variant_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:error_message, nil)
     |> assign_form_state(socket.assigns.variant, changeset, selected_positions)}
  end

  def handle_event("save", %{"exam_variant" => variant_params} = params, socket) do
    variant = socket.assigns.variant
    question_positions = parse_question_positions(params["variant_questions"] || %{})
    selected_positions = Map.new(question_positions)

    case Exams.save_exam_variant_with_questions(variant, variant_params, question_positions) do
      {:ok, saved_variant} ->
        socket =
          socket
          |> put_flash(:info, "Testvariante wurde erfolgreich gespeichert.")
          |> assign_form_state(
            saved_variant,
            Exams.change_exam_variant(saved_variant),
            selected_positions_for(saved_variant)
          )

        {:noreply, push_patch(socket, to: ~p"/admin/exam-variants/#{saved_variant}/edit")}

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, form_action(variant))

        {:noreply,
         socket
         |> assign(:error_message, "Bitte korrigiere die markierten Felder.")
         |> assign_form_state(variant, changeset, selected_positions)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error_message, format_variant_error(reason))
         |> assign_form_state(
           variant,
           Exams.change_exam_variant(variant || %ExamVariant{}, variant_params),
           selected_positions
         )}
    end
  end

  defp assign_form_state(socket, variant, changeset, selected_positions) do
    course_type = Ecto.Changeset.get_field(changeset, :course_type) || "F"

    questions =
      Exams.list_questions(status: "active", course_type: course_type)
      |> Repo.preload(:choices)

    socket
    |> assign(:variant, variant)
    |> assign(:form, to_form(changeset))
    |> assign(:questions, questions)
    |> assign(:selected_positions, selected_positions)
  end

  defp selected_positions_for(%ExamVariant{} = variant) do
    variant
    |> Exams.list_exam_variant_questions()
    |> Map.new(fn assignment -> {assignment.question_id, assignment.position} end)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_question_positions(question_params) when is_map(question_params) do
    question_params
    |> Enum.flat_map(fn {question_id, attrs} ->
      selected? = Map.get(attrs, "selected") == "true"

      with true <- selected?,
           {:ok, id} <- parse_id(question_id),
           {position, ""} <- Integer.parse(Map.get(attrs, "position", "")),
           true <- position > 0 do
        [{id, position}]
      else
        _ -> []
      end
    end)
  end

  defp parse_id(id), do: WhistleWeb.ControllerHelpers.parse_id(id)

  defp form_action(nil), do: :insert
  defp form_action(%ExamVariant{}), do: :update

  defp format_variant_error(:exam_variant_has_no_questions) do
    "Aktivierte Testvarianten benötigen mindestens eine Frage."
  end

  defp format_variant_error(:exam_variant_has_inactive_questions) do
    "Aktivierte Testvarianten dürfen nur aktive Fragen enthalten."
  end

  defp format_variant_error(:exam_variant_has_wrong_course_type_questions) do
    "Alle Fragen müssen zum Kurstyp der Testvariante passen."
  end

  defp format_variant_error(:exam_variant_duplicate_positions) do
    "Jede Position darf nur einmal vergeben werden."
  end

  defp format_variant_error(:exam_variant_duplicate_questions) do
    "Jede Frage darf nur einmal enthalten sein."
  end

  defp format_variant_error(:exam_variant_threshold_exceeds_max_points) do
    "Die Punktegrenzen dürfen die maximal erreichbare Punktzahl nicht überschreiten."
  end

  defp format_variant_error(reason),
    do: "Testvariante konnte nicht gespeichert werden: #{inspect(reason)}"

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn error -> translate_error(error) end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message -> "#{field_label(field)} #{message}" end)
    end)
  end

  defp visible_changeset_errors(%Ecto.Changeset{action: nil}), do: []
  defp visible_changeset_errors(%Ecto.Changeset{} = changeset), do: changeset_errors(changeset)

  defp field_label(:name), do: "Name"
  defp field_label(:course_type), do: "Kurstyp"
  defp field_label(:status), do: "Status"
  defp field_label(:duration_seconds), do: "Dauer"
  defp field_label(:l1_threshold), do: "L1-Grenze"
  defp field_label(:l2_threshold), do: "L2-Grenze"
  defp field_label(:l3_threshold), do: "L3-Grenze"
  defp field_label(:pass_threshold), do: "Bestehensgrenze"
  defp field_label(field), do: field |> Atom.to_string() |> String.replace("_", " ")

  defp status_label("draft"), do: "Entwurf"
  defp status_label("enabled"), do: "Aktiviert"
  defp status_label("disabled"), do: "Deaktiviert"
  defp status_label(status), do: status

  defp difficulty_label("low"), do: "Einfach"
  defp difficulty_label("medium"), do: "Mittel"
  defp difficulty_label("high"), do: "Schwer"
  defp difficulty_label(difficulty), do: difficulty

  defp type_label("single_choice"), do: "Eine Antwort"
  defp type_label("multiple_choice"), do: "Multiple-Choice"
  defp type_label("text"), do: "Text"
  defp type_label(type), do: type

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <.header class="mb-2">
      Testvarianten
      <:actions>
        <.button navigate={~p"/admin/exam-variants/new"}>Neue Testvariante</.button>
      </:actions>
    </.header>

    <div class="mb-6 flex items-start justify-between gap-4">
      <form id="exam-variant-filter-form" phx-change="filter" class="flex items-center gap-3">
        <select
          id="exam-variant-filter-course-type"
          name="course_type"
          class="rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-blue-500 focus:outline-none"
        >
          <option value="">Alle Kurstypen</option>
          <%= for course_type <- @course_types do %>
            <option value={course_type} selected={course_type == @filter_course_type}>
              {course_type}
            </option>
          <% end %>
        </select>
        <select
          id="exam-variant-filter-status"
          name="status"
          class="rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-blue-500 focus:outline-none"
        >
          <option value="">Alle Status</option>
          <%= for status <- @statuses do %>
            <option value={status} selected={status == @filter_status}>
              {status_label(status)}
            </option>
          <% end %>
        </select>
      </form>
    </div>

    <div id="exam-variants" class="space-y-3">
      <%= for variant <- @variants do %>
        <.link
          navigate={~p"/admin/exam-variants/#{variant}/edit"}
          class="block rounded-lg border border-gray-200 bg-white px-5 py-4 shadow-sm transition-colors hover:border-gray-300"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <h3 class="truncate text-sm font-semibold text-gray-900">{variant.name}</h3>
                <span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600">
                  {variant.course_type}
                </span>
              </div>
              <div class="mt-1 text-xs text-gray-500">
                {length(variant.variant_questions)} Fragen · {div(variant.duration_seconds, 60)} Minuten
              </div>
            </div>
            <span class={[
              "shrink-0 rounded-full px-2 py-0.5 text-xs font-medium",
              variant.status == "enabled" && "bg-green-100 text-green-700",
              variant.status == "draft" && "bg-yellow-100 text-yellow-800",
              variant.status == "disabled" && "bg-gray-100 text-gray-500"
            ]}>
              {status_label(variant.status)}
            </span>
          </div>
        </.link>
      <% end %>

      <p :if={@variants == []} class="py-10 text-center text-sm text-base-content/50">
        Keine Testvarianten gefunden.
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <% errors = visible_changeset_errors(@form.source) %>

    <.breadcrumbs>
      <:item navigate={~p"/admin/exam-variants"}>Testvarianten</:item>
      <:item>{@page_title}</:item>
    </.breadcrumbs>

    <.header class="mt-4">
      {@page_title}
      <:subtitle>
        Eine aktivierte Testvariante kann beim Erstellen eines Tests ausgewählt werden.
      </:subtitle>
    </.header>

    <div
      :if={@error_message || errors != []}
      id="exam-variant-error-summary"
      class="mt-4 max-w-3xl rounded-lg border border-error/25 bg-error/8 px-4 py-3 text-sm text-error"
    >
      <p :if={@error_message} class="font-medium">{@error_message}</p>
      <ul :if={errors != []} class="mt-2 list-disc space-y-1 pl-5">
        <li :for={message <- errors}>{message}</li>
      </ul>
    </div>

    <.form
      for={@form}
      id="exam-variant-form"
      phx-change="validate"
      phx-submit="save"
      class="mt-6 max-w-3xl space-y-8"
    >
      <div class="space-y-5">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:name]} id="exam-variant-name" type="text" label="Name" required />
          <.input
            field={@form[:course_type]}
            id="exam-variant-course-type"
            type="select"
            label="Kurstyp"
            options={Enum.map(@course_types, &{&1, &1})}
          />
          <.input
            field={@form[:status]}
            id="exam-variant-status"
            type="select"
            label="Status"
            options={Enum.map(@statuses, &{status_label(&1), &1})}
          />
          <.input
            field={@form[:duration_seconds]}
            id="exam-variant-duration-seconds"
            type="number"
            label="Dauer in Sekunden"
            min="1"
            required
          />
        </div>

        <div class="grid gap-4 sm:grid-cols-4">
          <.input
            field={@form[:l1_threshold]}
            id="exam-variant-l1-threshold"
            type="number"
            label="L1-Grenze"
            min="0"
          />
          <.input
            field={@form[:l2_threshold]}
            id="exam-variant-l2-threshold"
            type="number"
            label="L2-Grenze"
            min="0"
          />
          <.input
            field={@form[:l3_threshold]}
            id="exam-variant-l3-threshold"
            type="number"
            label="L3-Grenze"
            min="0"
          />
          <.input
            field={@form[:pass_threshold]}
            id="exam-variant-pass-threshold"
            type="number"
            label="Bestehensgrenze"
            min="0"
          />
        </div>
      </div>

      <div>
        <div class="mb-3 flex items-end justify-between gap-4">
          <div>
            <h2 class="text-sm font-semibold text-gray-900">Fragen</h2>
            <p class="mt-1 text-xs text-gray-500">
              Die Position bestimmt die Reihenfolge im Test.
            </p>
          </div>
          <span id="exam-variant-question-count" class="text-xs text-gray-500">
            {map_size(@selected_positions)} von {length(@questions)} ausgewählt
          </span>
        </div>

        <div
          id="exam-variant-questions"
          class="divide-y divide-gray-100 rounded-lg border border-gray-200 bg-white"
        >
          <%= for {question, index} <- Enum.with_index(@questions, 1) do %>
            <% position = Map.get(@selected_positions, question.id, index) %>
            <label
              id={"exam-variant-question-#{question.id}"}
              class="flex items-start gap-3 px-4 py-3 transition-colors hover:bg-gray-50"
            >
              <input
                id={"exam-variant-question-#{question.id}-selected"}
                type="checkbox"
                name={"variant_questions[#{question.id}][selected]"}
                value="true"
                checked={Map.has_key?(@selected_positions, question.id)}
                class="mt-1 rounded border-gray-300 text-blue-600"
              />
              <input
                id={"exam-variant-question-#{question.id}-position"}
                type="number"
                name={"variant_questions[#{question.id}][position]"}
                value={position}
                min="1"
                class="w-20 rounded-md border border-gray-300 px-2 py-1 text-sm"
                aria-label={"Position für Frage #{question.id}"}
              />
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-2 text-xs text-gray-500">
                  <span>{difficulty_label(question.difficulty)}</span>
                  <span>·</span>
                  <span>{type_label(question.type)}</span>
                </div>
                <p class="mt-1 truncate text-sm text-gray-800">{question.body_markdown}</p>
              </div>
            </label>
          <% end %>

          <p :if={@questions == []} class="px-4 py-8 text-center text-sm text-gray-500">
            Keine aktiven Fragen für diesen Kurstyp.
          </p>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <.button type="submit">Speichern</.button>
        <.button navigate={~p"/admin/exam-variants"}>Zurück</.button>
      </div>
    </.form>
    """
  end
end
