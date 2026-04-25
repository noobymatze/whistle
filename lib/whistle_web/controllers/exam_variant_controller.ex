defmodule WhistleWeb.ExamVariantController do
  use WhistleWeb, :controller

  alias Whistle.Exams
  alias Whistle.Exams.ExamVariant

  plug WhistleWeb.Plugs.RequireRole, course_area: true

  def index(conn, params) do
    course_type = params["course_type"]
    status = params["status"]

    opts =
      []
      |> maybe_put(:course_type, course_type)
      |> maybe_put(:status, status)

    variants =
      opts
      |> Exams.list_exam_variants()
      |> Whistle.Repo.preload(:variant_questions)

    render(conn, :index,
      variants: variants,
      filter_course_type: course_type || "",
      filter_status: status || "",
      course_types: ExamVariant.valid_course_types(),
      statuses: ExamVariant.valid_statuses()
    )
  end

  def new(conn, _params) do
    changeset =
      Exams.change_exam_variant(%ExamVariant{
        course_type: "F",
        status: "draft",
        duration_seconds: 30 * 60
      })

    render_edit(conn, nil, changeset)
  end

  def create(conn, %{"exam_variant" => variant_params}) do
    case Exams.create_exam_variant(variant_params) do
      {:ok, variant} ->
        conn
        |> put_flash(:info, "Testvariante wurde erfolgreich erstellt.")
        |> redirect(to: ~p"/admin/exam-variants/#{variant}/edit")

      {:error, changeset} ->
        render_edit(conn, nil, changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %ExamVariant{} = variant <- get_variant(id) do
      render_edit(conn, variant, Exams.change_exam_variant(variant))
    else
      _ -> render_not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "exam_variant" => variant_params}) do
    with {:ok, id} <- parse_id(id),
         %ExamVariant{} = variant <- get_variant(id) do
      case Exams.update_exam_variant(variant, variant_params) do
        {:ok, variant} ->
          conn
          |> put_flash(:info, "Testvariante wurde erfolgreich aktualisiert.")
          |> redirect(to: ~p"/admin/exam-variants/#{variant}/edit")

        {:error, %Ecto.Changeset{} = changeset} ->
          render_edit(conn, variant, changeset)

        {:error, reason} ->
          conn
          |> put_flash(:error, format_variant_error(reason))
          |> redirect(to: ~p"/admin/exam-variants/#{variant}/edit")
      end
    else
      _ -> render_not_found(conn)
    end
  end

  def update_questions(conn, %{"id" => id} = params) do
    with {:ok, id} <- parse_id(id),
         %ExamVariant{} = variant <- get_variant(id) do
      question_positions = parse_question_positions(params["variant_questions"] || %{})

      case Exams.set_exam_variant_questions(variant, question_positions) do
        {:ok, _variant} ->
          conn
          |> put_flash(:info, "Fragen der Testvariante wurden aktualisiert.")
          |> redirect(to: ~p"/admin/exam-variants/#{variant}/edit")

        {:error, reason} ->
          conn
          |> put_flash(:error, format_variant_error(reason))
          |> redirect(to: ~p"/admin/exam-variants/#{variant}/edit")
      end
    else
      _ -> render_not_found(conn)
    end
  end

  defp render_edit(conn, variant, changeset) do
    assignments =
      if variant do
        Exams.list_exam_variant_questions(variant)
      else
        []
      end

    selected_positions =
      Map.new(assignments, fn assignment ->
        {assignment.question_id, assignment.position}
      end)

    course_type = Ecto.Changeset.get_field(changeset, :course_type) || "F"

    questions =
      Exams.list_questions(status: "active", course_type: course_type)
      |> Whistle.Repo.preload(:choices)

    render(conn, :edit,
      variant: variant,
      form: Phoenix.Component.to_form(changeset),
      questions: questions,
      selected_positions: selected_positions,
      course_types: ExamVariant.valid_course_types(),
      statuses: ExamVariant.valid_statuses()
    )
  end

  defp get_variant(id) do
    Whistle.Repo.get(ExamVariant, id)
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
end
