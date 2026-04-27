defmodule WhistleWeb.QuestionController do
  use WhistleWeb, :controller

  alias Whistle.Exams
  alias Whistle.Exams.Question
  alias Whistle.Exams.QuestionChoice

  plug WhistleWeb.Plugs.RequireRole, course_area: true
  plug WhistleWeb.Plugs.RequireRole, [role: "SUPER_ADMIN"] when action == :delete

  def index(conn, params) do
    status = params["status"]
    course_type = params["course_type"]

    opts =
      []
      |> then(fn o -> if status && status != "", do: Keyword.put(o, :status, status), else: o end)
      |> then(fn o ->
        if course_type && course_type != "",
          do: Keyword.put(o, :course_type, course_type),
          else: o
      end)

    questions =
      Exams.list_questions(opts)
      |> Whistle.Repo.preload(:course_type_assignments)

    exam_variants =
      Exams.list_exam_variants()
      |> Whistle.Repo.preload(:variant_questions)

    render(conn, :index,
      questions: questions,
      exam_variants: exam_variants,
      filter_status: status || "",
      filter_course_type: course_type || "",
      statuses: Question.valid_statuses(),
      course_types: ~w(F J G)
    )
  end

  def new(conn, _params) do
    changeset = Exams.change_question(%Question{})

    render(conn, :edit,
      question: nil,
      changeset: changeset,
      choice_changesets: [blank_choice_changeset(1), blank_choice_changeset(2)],
      course_type_assignments: [],
      exam_variants: exam_variants_for_form(),
      selected_exam_variant_ids: [],
      types: Question.valid_types(),
      difficulties: Question.valid_difficulties(),
      statuses: Question.valid_statuses()
    )
  end

  def create(conn, %{"question" => question_params} = params) do
    user = conn.assigns.current_user
    attrs = Map.put(question_params, "created_by", user.id)

    case Exams.create_question(attrs) do
      {:ok, question} ->
        question = Exams.get_question_with_details!(question.id)
        save_choices(question, params["choices"] || %{})
        save_course_types(question, params["course_types"] || [])
        save_exam_variants(question, params["exam_variants"] || [])

        conn
        |> put_flash(:info, "Frage wurde erfolgreich erstellt.")
        |> redirect(to: ~p"/admin/questions/#{question}/edit")

      {:error, changeset} ->
        render(conn, :edit,
          question: nil,
          changeset: changeset,
          choice_changesets: build_choice_changesets(params["choices"] || %{}),
          course_type_assignments: params["course_types"] || [],
          exam_variants: exam_variants_for_form(),
          selected_exam_variant_ids: parse_selected_variant_ids(params["exam_variants"] || []),
          types: Question.valid_types(),
          difficulties: Question.valid_difficulties(),
          statuses: Question.valid_statuses(),
          scoring_modes: Question.valid_scoring_modes()
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %Question{} = question <- Exams.get_question_with_details(id) do
      changeset = Exams.change_question(question)

      existing_choice_changesets =
        question.choices
        |> Enum.map(&Exams.change_question_choice/1)

      choice_changesets =
        if length(existing_choice_changesets) < 2 do
          next_pos = length(existing_choice_changesets) + 1
          existing_choice_changesets ++ [blank_choice_changeset(next_pos)]
        else
          existing_choice_changesets
        end

      course_types =
        question.course_type_assignments
        |> Enum.map(& &1.course_type)

      selected_exam_variant_ids =
        question.variant_assignments
        |> Enum.map(& &1.exam_variant_id)

      render(conn, :edit,
        question: question,
        changeset: changeset,
        choice_changesets: choice_changesets,
        course_type_assignments: course_types,
        exam_variants: exam_variants_for_form(),
        selected_exam_variant_ids: selected_exam_variant_ids,
        types: Question.valid_types(),
        difficulties: Question.valid_difficulties(),
        statuses: Question.valid_statuses()
      )
    else
      _ -> render_not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "question" => question_params} = params) do
    with {:ok, id} <- parse_id(id),
         %Question{} = question <- Exams.get_question_with_details(id) do
      case Exams.update_question(question, question_params) do
        {:ok, question} ->
          save_choices(question, params["choices"] || %{})
          save_course_types(question, params["course_types"] || [])
          save_exam_variants(question, params["exam_variants"] || [])

          conn
          |> put_flash(:info, "Frage wurde erfolgreich aktualisiert.")
          |> redirect(to: ~p"/admin/questions/#{question}/edit")

        {:error, changeset} ->
          render(conn, :edit,
            question: question,
            changeset: changeset,
            choice_changesets: build_choice_changesets(params["choices"] || %{}),
            course_type_assignments: params["course_types"] || [],
            exam_variants: exam_variants_for_form(),
            selected_exam_variant_ids: parse_selected_variant_ids(params["exam_variants"] || []),
            types: Question.valid_types(),
            difficulties: Question.valid_difficulties(),
            statuses: Question.valid_statuses(),
            scoring_modes: Question.valid_scoring_modes()
          )
      end
    else
      _ -> render_not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %Question{} = question <- Exams.get_question(id) do
      {:ok, _} = Exams.delete_question(question)

      conn
      |> put_flash(:info, "Frage wurde erfolgreich gelöscht.")
      |> redirect(to: ~p"/admin/questions")
    else
      _ -> render_not_found(conn)
    end
  end

  def activate(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %Question{} = question <- Exams.get_question(id) do
      {:ok, _} = Exams.update_question(question, %{status: "active"})

      conn
      |> put_flash(:info, "Frage wurde aktiviert.")
      |> redirect(to: ~p"/admin/questions")
    else
      _ -> render_not_found(conn)
    end
  end

  def deactivate(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %Question{} = question <- Exams.get_question(id) do
      {:ok, _} = Exams.update_question(question, %{status: "archived"})

      conn
      |> put_flash(:info, "Frage wurde deaktiviert.")
      |> redirect(to: ~p"/admin/questions")
    else
      _ -> render_not_found(conn)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp save_choices(question, choices_params) when is_map(choices_params) do
    # Delete all existing choices and recreate from submitted params
    question.choices
    |> Enum.each(fn choice ->
      Exams.delete_question_choice(choice)
    end)

    choices_params
    |> Enum.sort_by(fn {key, _} -> choice_position(key) end)
    |> Enum.with_index(1)
    |> Enum.each(fn {{_k, choice_attrs}, position} ->
      body = Map.get(choice_attrs, "body_markdown", "") |> String.trim()

      if body != "" do
        Exams.create_question_choice(%{
          question_id: question.id,
          body_markdown: body,
          position: position,
          is_correct: Map.get(choice_attrs, "is_correct", "false") == "true"
        })
      end
    end)
  end

  defp save_choices(question, _choices_params) do
    question.choices |> Enum.each(&Exams.delete_question_choice/1)
  end

  defp save_course_types(question, course_types) when is_list(course_types) do
    valid = Enum.filter(course_types, fn ct -> ct in ~w(F J G) end)
    Exams.set_question_course_types(question, valid)
  end

  defp save_course_types(question, _), do: Exams.set_question_course_types(question, [])

  defp save_exam_variants(question, variant_ids) when is_list(variant_ids) do
    Exams.set_question_exam_variants(question, parse_selected_variant_ids(variant_ids))
  end

  defp save_exam_variants(question, _), do: Exams.set_question_exam_variants(question, [])

  defp parse_selected_variant_ids(variant_ids) when is_list(variant_ids) do
    variant_ids
    |> Enum.flat_map(fn id ->
      case parse_id(id) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
  end

  defp parse_selected_variant_ids(_), do: []

  defp exam_variants_for_form do
    Exams.list_exam_variants()
    |> Whistle.Repo.preload(:variant_questions)
  end

  defp blank_choice_changeset(position) do
    Exams.change_question_choice(%QuestionChoice{position: position, is_correct: false})
  end

  defp build_choice_changesets(choices_params) when is_map(choices_params) do
    if map_size(choices_params) == 0 do
      [blank_choice_changeset(1), blank_choice_changeset(2)]
    else
      choices_params
      |> Enum.sort_by(fn {key, _} -> choice_position(key) end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{_k, attrs}, pos} ->
        Exams.change_question_choice(%QuestionChoice{position: pos}, attrs)
      end)
    end
  end

  defp build_choice_changesets(_), do: [blank_choice_changeset(1), blank_choice_changeset(2)]

  defp choice_position(key) do
    case parse_id(key) do
      {:ok, position} -> position
      :error -> 0
    end
  end
end
