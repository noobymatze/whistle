defmodule Whistle.Exams do
  @moduledoc """
  The Exams context.

  Responsible for question management, exam creation, snapshot handling,
  participation tracking, and scoring.
  """

  import Ecto.Query, warn: false
  alias Whistle.Repo

  alias Whistle.Exams.{
    Question,
    QuestionChoice,
    QuestionCourseType,
    CourseTypeQuestionDistribution,
    Exam,
    ExamParticipant,
    ExamQuestion,
    ExamQuestionChoice,
    ExamAnswer,
    ExamAnswerChoice
  }

  # ---------------------------------------------------------------------------
  # Questions
  # ---------------------------------------------------------------------------

  @doc """
  Returns all questions, optionally filtered.

  ## Options

    * `:status` - Filter by status (e.g. "active")
    * `:course_type` - Filter to questions assigned to this course type
    * `:difficulty` - Filter by difficulty

  """
  def list_questions(opts \\ []) do
    status = Keyword.get(opts, :status)
    course_type = Keyword.get(opts, :course_type)
    difficulty = Keyword.get(opts, :difficulty)

    query = from(q in Question)

    query =
      if status do
        from(q in query, where: q.status == ^status)
      else
        query
      end

    query =
      if course_type do
        from(q in query,
          join: qct in QuestionCourseType,
          on: qct.question_id == q.id and qct.course_type == ^course_type
        )
      else
        query
      end

    query =
      if difficulty do
        from(q in query, where: q.difficulty == ^difficulty)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single question.

  Raises `Ecto.NoResultsError` if the Question does not exist.
  """
  def get_question!(id), do: Repo.get!(Question, id)

  @doc """
  Gets a single question.

  Returns `nil` if the Question does not exist.
  """
  def get_question(id), do: Repo.get(Question, id)

  @doc """
  Gets a single question with preloaded choices and course type assignments.
  """
  def get_question_with_details!(id) do
    Question
    |> Repo.get!(id)
    |> Repo.preload([:choices, :course_type_assignments])
  end

  @doc """
  Gets a single question with preloaded choices and course type assignments.

  Returns `nil` if the Question does not exist.
  """
  def get_question_with_details(id) do
    case Repo.get(Question, id) do
      nil -> nil
      question -> Repo.preload(question, [:choices, :course_type_assignments])
    end
  end

  @doc """
  Creates a question.
  """
  def create_question(attrs \\ %{}) do
    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a question.
  """
  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a question.
  """
  def delete_question(%Question{} = question) do
    Repo.delete(question)
  end

  @doc """
  Returns a changeset for a question.
  """
  def change_question(%Question{} = question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  # ---------------------------------------------------------------------------
  # Question Choices
  # ---------------------------------------------------------------------------

  @doc """
  Lists choices for a question.
  """
  def list_question_choices(question_id) do
    from(c in QuestionChoice,
      where: c.question_id == ^question_id,
      order_by: [asc: c.position]
    )
    |> Repo.all()
  end

  @doc """
  Creates a question choice.
  """
  def create_question_choice(attrs \\ %{}) do
    %QuestionChoice{}
    |> QuestionChoice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a question choice.
  """
  def update_question_choice(%QuestionChoice{} = choice, attrs) do
    choice
    |> QuestionChoice.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a question choice.
  """
  def delete_question_choice(%QuestionChoice{} = choice) do
    Repo.delete(choice)
  end

  @doc """
  Returns a changeset for a question choice.
  """
  def change_question_choice(%QuestionChoice{} = choice, attrs \\ %{}) do
    QuestionChoice.changeset(choice, attrs)
  end

  # ---------------------------------------------------------------------------
  # Question Course Type Assignments
  # ---------------------------------------------------------------------------

  @doc """
  Sets the course type assignments for a question.

  Replaces all existing assignments with the given list of course types.
  """
  def set_question_course_types(%Question{} = question, course_types)
      when is_list(course_types) do
    Repo.transaction(fn ->
      from(qct in QuestionCourseType, where: qct.question_id == ^question.id)
      |> Repo.delete_all()

      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      results =
        Enum.map(course_types, fn ct ->
          %QuestionCourseType{}
          |> QuestionCourseType.changeset(%{
            question_id: question.id,
            course_type: ct
          })
          |> Ecto.Changeset.put_change(:created_at, now)
          |> Repo.insert()
        end)

      errors = Enum.filter(results, fn {status, _} -> status == :error end)

      if Enum.empty?(errors) do
        Enum.map(results, fn {:ok, qct} -> qct end)
      else
        {:error, errors} |> Repo.rollback()
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Course Type Question Distributions
  # ---------------------------------------------------------------------------

  @doc """
  Gets the distribution config for a course type, or returns defaults.
  """
  def get_distribution_for_course_type(course_type) do
    case Repo.get_by(CourseTypeQuestionDistribution, course_type: course_type) do
      nil -> struct(CourseTypeQuestionDistribution, CourseTypeQuestionDistribution.defaults())
      dist -> dist
    end
  end

  @doc """
  Randomly selects questions for a course type according to its distribution.

  Returns `{:ok, [question]}` or `{:error, {:not_enough_questions, difficulty, needed, available}}`.
  """
  def select_questions_for_course_type(course_type) do
    distribution = get_distribution_for_course_type(course_type)
    counts = calculate_difficulty_counts(distribution.question_count, distribution)
    load_and_select_questions(course_type, counts)
  end

  @doc """
  Lists all configured distributions.
  """
  def list_distributions do
    Repo.all(CourseTypeQuestionDistribution)
  end

  @doc """
  Creates or updates a distribution for a course type.
  """
  def upsert_distribution(attrs) do
    course_type = Map.get(attrs, :course_type) || Map.get(attrs, "course_type")

    case Repo.get_by(CourseTypeQuestionDistribution, course_type: course_type) do
      nil ->
        %CourseTypeQuestionDistribution{}
        |> CourseTypeQuestionDistribution.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> CourseTypeQuestionDistribution.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Returns a changeset for a distribution.
  """
  def change_distribution(%CourseTypeQuestionDistribution{} = dist, attrs \\ %{}) do
    CourseTypeQuestionDistribution.changeset(dist, attrs)
  end

  # ---------------------------------------------------------------------------
  # Exams
  # ---------------------------------------------------------------------------

  @doc """
  Lists exams, optionally filtered.

  ## Options

    * `:course_id` - Filter by course

  """
  def list_exams(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)

    query = from(e in Exam, order_by: [desc: e.created_at])

    query =
      if course_id do
        from(e in query, where: e.course_id == ^course_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single exam.

  Raises `Ecto.NoResultsError` if the Exam does not exist.
  """
  def get_exam!(id), do: Repo.get!(Exam, id)

  @doc """
  Gets a single exam.

  Returns `nil` if the Exam does not exist.
  """
  def get_exam(id), do: Repo.get(Exam, id)

  @doc """
  Gets an exam with participants and questions preloaded.
  """
  def get_exam_with_details!(id) do
    Exam
    |> Repo.get!(id)
    |> Repo.preload([:participants, questions: :choices])
  end

  @doc """
  Gets an exam with participants and questions preloaded.

  Returns `nil` if the Exam does not exist.
  """
  def get_exam_with_details(id) do
    case Repo.get(Exam, id) do
      nil -> nil
      exam -> Repo.preload(exam, [:participants, questions: :choices])
    end
  end

  @doc """
  Creates an exam with a snapshot of selected questions and participants.

  This is the main exam creation entry point. It:
  1. Loads the course type distribution (or defaults)
  2. Selects questions by difficulty distribution
  3. Creates the exam record
  4. Copies questions and choices into snapshot tables
  5. Creates exam_participant records for selected user IDs

  Returns `{:ok, exam}` or `{:error, reason}`.

  Possible error reasons:
  - `{:not_enough_questions, difficulty, needed, available}` - not enough questions for a difficulty level
  """
  def create_exam(course, user_ids, created_by_user_id, opts \\ []) do
    show_countdown = Keyword.get(opts, :show_countdown_to_participants, false)
    execution_mode = Keyword.get(opts, :execution_mode, "synchronous")
    preselected = Keyword.get(opts, :questions)

    active_states = ["waiting_room", "running", "paused"]

    conflicting_user_ids =
      from(p in ExamParticipant,
        join: e in Exam,
        on: e.id == p.exam_id,
        where: p.user_id in ^user_ids and e.course_id == ^course.id and e.state in ^active_states,
        select: p.user_id
      )
      |> Repo.all()

    if conflicting_user_ids != [] do
      {:error, {:already_in_active_exam, conflicting_user_ids}}
    else
      Repo.transaction(fn ->
        distribution = get_distribution_for_course_type(course.type)
        question_count = distribution.question_count

        questions_result =
          if preselected do
            {:ok, preselected}
          else
            counts = calculate_difficulty_counts(question_count, distribution)
            load_and_select_questions(course.type, counts)
          end

        case questions_result do
          {:error, reason} ->
            Repo.rollback(reason)

          {:ok, selected_questions} ->
            now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

            initial_state =
              if execution_mode == "asynchronous", do: "running", else: "waiting_room"

            {:ok, exam} =
              %Exam{}
              |> Exam.changeset(%{
                course_id: course.id,
                course_type: course.type,
                state: initial_state,
                execution_mode: execution_mode,
                question_count: length(selected_questions),
                duration_seconds: distribution.duration_seconds,
                l1_threshold: distribution.l1_threshold,
                l2_threshold: distribution.l2_threshold,
                l3_threshold: distribution.l3_threshold,
                pass_threshold: distribution.pass_threshold,
                show_countdown_to_participants: show_countdown,
                created_by: created_by_user_id
              })
              |> Repo.insert()

            snapshot_questions(exam, selected_questions, now)
            create_exam_participants(exam, user_ids, now)

            exam
        end
      end)
    end
  end

  @doc """
  Updates an exam's state.
  """
  def update_exam_state(%Exam{} = exam, new_state) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    attrs =
      case new_state do
        "running" -> %{state: "running", started_at: now}
        "paused" -> %{state: "paused", paused_at: now}
        "finished" -> %{state: "finished", ended_at: now}
        "canceled" -> %{state: "canceled", ended_at: now}
        _ -> %{state: new_state}
      end

    exam
    |> Exam.changeset(attrs)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Exam Participants
  # ---------------------------------------------------------------------------

  @doc """
  Gets an exam participant by exam and user.
  """
  def get_exam_participant(exam_id, user_id) do
    Repo.get_by(ExamParticipant, exam_id: exam_id, user_id: user_id)
  end

  @async_duration_seconds 30 * 60

  @doc """
  Starts the async attempt for a participant who hasn't started yet.

  Sets `async_started_at` and `async_deadline_at` (30 minutes from now),
  transitions the participant to `running`, and is idempotent — calling it
  again on an already-started participant returns `{:error, :already_started}`.
  """
  def start_async_participant(%ExamParticipant{} = participant) do
    if participant.async_started_at != nil do
      {:error, :already_started}
    else
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      deadline = NaiveDateTime.add(now, @async_duration_seconds, :second)

      participant
      |> ExamParticipant.changeset(%{
        state: "running",
        async_started_at: now,
        async_deadline_at: deadline,
        connected_at: now,
        last_seen_at: now
      })
      |> Repo.update()
    end
  end

  @doc """
  Cancels an async participant's own attempt and records it as a fail.

  Only valid for asynchronous exams. Sets the participant to submitted with
  zero points and a fail outcome so the instructor can see it and create a
  new exam for that participant if needed.
  """
  def cancel_async_participant(%ExamParticipant{} = participant) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    participant
    |> ExamParticipant.changeset(%{
      state: "submitted",
      submitted_at: now,
      score: 0,
      max_score: participant.max_points || 0,
      passed: false,
      achieved_points: 0,
      exam_outcome: "fail",
      license_decision: "denied",
      l1_review_eligible: false
    })
    |> Repo.update()
  end

  @doc """
  Returns true if the participant's async deadline has passed.
  """
  def async_deadline_passed?(%ExamParticipant{async_deadline_at: nil}), do: false

  def async_deadline_passed?(%ExamParticipant{async_deadline_at: deadline}) do
    now = NaiveDateTime.utc_now()
    NaiveDateTime.compare(now, deadline) != :lt
  end

  @doc """
  Updates an exam participant's state.
  """
  def update_participant_state(%ExamParticipant{} = participant, new_state) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    attrs =
      case new_state do
        "submitted" -> %{state: "submitted", submitted_at: now}
        "connected" -> %{state: "running", connected_at: now, last_seen_at: now}
        "disconnected" -> %{state: "disconnected", disconnected_at: now}
        _ -> %{state: new_state}
      end

    participant
    |> ExamParticipant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a participant as seen (heartbeat).
  """
  def touch_participant(%ExamParticipant{} = participant) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    participant
    |> ExamParticipant.changeset(%{last_seen_at: now})
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Exam Answers
  # ---------------------------------------------------------------------------

  @doc """
  Records or updates an answer for a participant's question.

  For choice questions, `choice_ids` should be the list of selected `exam_question_choice_id` values.
  """
  def upsert_answer(exam_participant, exam_question, choice_ids \\ []) do
    if async_deadline_passed?(exam_participant) do
      {:error, :deadline_passed}
    else
      do_upsert_answer(exam_participant, exam_question, choice_ids)
    end
  end

  defp do_upsert_answer(exam_participant, exam_question, choice_ids) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Repo.transaction(fn ->
      existing =
        Repo.get_by(ExamAnswer,
          exam_participant_id: exam_participant.id,
          exam_question_id: exam_question.id
        )

      answer_attrs = %{
        exam_id: exam_participant.exam_id,
        exam_participant_id: exam_participant.id,
        exam_question_id: exam_question.id,
        user_id: exam_participant.user_id,
        question_type: exam_question.type,
        answered_at: now
      }

      {:ok, answer} =
        case existing do
          nil ->
            %ExamAnswer{}
            |> ExamAnswer.changeset(answer_attrs)
            |> Repo.insert()

          existing_answer ->
            existing_answer
            |> ExamAnswer.changeset(answer_attrs)
            |> Repo.update()
        end

      if exam_question.type in ["single_choice", "multiple_choice"] do
        from(eac in ExamAnswerChoice, where: eac.exam_answer_id == ^answer.id)
        |> Repo.delete_all()

        Enum.each(choice_ids, fn choice_id ->
          %ExamAnswerChoice{}
          |> ExamAnswerChoice.changeset(%{
            exam_answer_id: answer.id,
            exam_question_choice_id: choice_id,
            created_at: now
          })
          |> Repo.insert!()
        end)
      end

      answer
    end)
  end

  @doc """
  Returns all answers for a participant, preloaded with answer choices.
  """
  def list_answers_for_participant(exam_participant_id) do
    from(a in ExamAnswer,
      where: a.exam_participant_id == ^exam_participant_id
    )
    |> Repo.all()
    |> Repo.preload(:answer_choices)
  end

  # ---------------------------------------------------------------------------
  # Distribution calculation helpers
  # ---------------------------------------------------------------------------

  @doc """
  Calculates how many questions of each difficulty to pick.

  Uses largest-remainder rounding to ensure the total equals `question_count`.
  """
  def calculate_difficulty_counts(question_count, distribution) do
    low_exact = question_count * distribution.low_percentage / 100
    medium_exact = question_count * distribution.medium_percentage / 100
    high_exact = question_count * distribution.high_percentage / 100

    # Floor all values
    low_floor = trunc(low_exact)
    medium_floor = trunc(medium_exact)
    high_floor = trunc(high_exact)

    remainder = question_count - low_floor - medium_floor - high_floor

    # Distribute remainder by largest fractional parts
    remainders =
      [
        {:low, low_exact - low_floor},
        {:medium, medium_exact - medium_floor},
        {:high, high_exact - high_floor}
      ]
      |> Enum.sort_by(fn {_, frac} -> -frac end)

    {adjustments, _} =
      Enum.reduce(remainders, {%{low: 0, medium: 0, high: 0}, remainder}, fn
        {_key, _}, {acc, 0} -> {acc, 0}
        {key, _}, {acc, rem} -> {Map.put(acc, key, 1), rem - 1}
      end)

    %{
      low: low_floor + adjustments.low,
      medium: medium_floor + adjustments.medium,
      high: high_floor + adjustments.high
    }
  end

  # ---------------------------------------------------------------------------
  # Scoring and results
  # ---------------------------------------------------------------------------

  @doc """
  Scores all participants in an exam.

  For each participant:
  1. Loads their answers (unanswered questions are treated as 0 points — no empty rows created).
  2. Computes score using `Whistle.Exams.Scoring`.
  3. Updates `exam_participants` with score, max_score, passed, and license_decision.
  4. For participants who passed, issues a provisional license.

  Broadcasts `{:exam_scored, exam}` when done.
  """
  def score_exam(%Exam{} = exam) do
    exam = Repo.preload(exam, participants: [], questions: :choices)
    questions = exam.questions

    Enum.each(exam.participants, fn participant ->
      answers = list_answers_for_participant(participant.id)

      question_answer_pairs =
        Enum.map(questions, fn question ->
          answer = Enum.find(answers, fn a -> a.exam_question_id == question.id end)

          choice_ids =
            if answer do
              answer
              |> Repo.preload(:answer_choices)
              |> Map.get(:answer_choices)
              |> Enum.map(& &1.exam_question_choice_id)
            else
              []
            end

          {question, choice_ids}
        end)

      result =
        Whistle.Exams.Scoring.compute_total(
          question_answer_pairs,
          exam
        )

      passed = result.outcome in [:l3_pass, :l2_pass, :l1_eligible]
      license_decision = if passed, do: "granted", else: "denied"
      l1_review_eligible = result.outcome == :l1_eligible

      participant
      |> ExamParticipant.changeset(%{
        score: result.achieved_points,
        max_score: result.max_points,
        passed: passed,
        license_decision: license_decision,
        achieved_points: result.achieved_points,
        max_points: result.max_points,
        exam_outcome: Atom.to_string(result.outcome),
        l1_review_eligible: l1_review_eligible
      })
      |> Repo.update!()

      if passed do
        issue_seasonal_license(participant, exam, result.outcome)
      end
    end)

    broadcast(exam.id, {:exam_scored, exam})
    :ok
  end

  @doc """
  Issues or updates the seasonal license for a participant who passed.

  The license type is determined by course type and exam outcome:
  - F-course l1_eligible → :L2 (manual L1 review is tracked on the participant)
  - F-course l2_pass     → :L2
  - F-course l3_pass     → :L3
  - G-course l3_pass     → :L3
  - J-course             → :LJ (not triggered via online scoring)

  Upserts the license for the exam's course season so re-scoring is idempotent.
  """
  def issue_seasonal_license(participant, exam, outcome) do
    license_type = outcome_to_license_type(exam.course_type, outcome)

    if license_type do
      season_id = get_season_id_for_exam(exam)

      if season_id do
        upsert_seasonal_license(participant.user_id, season_id, license_type)
      end
    end
  end

  defp get_season_id_for_exam(%{course_id: course_id}) when not is_nil(course_id) do
    case Repo.get(Whistle.Courses.Course, course_id) do
      nil -> nil
      course -> course.season_id
    end
  end

  defp get_season_id_for_exam(_), do: nil

  defp upsert_seasonal_license(user_id, season_id, license_type) do
    case Repo.get_by(Whistle.Accounts.License, user_id: user_id, season_id: season_id) do
      nil ->
        Repo.insert(
          Whistle.Accounts.License.changeset(%Whistle.Accounts.License{}, %{
            type: license_type,
            season_id: season_id,
            user_id: user_id,
            created_by: user_id
          })
        )

      existing ->
        existing
        |> Whistle.Accounts.License.changeset(%{type: license_type})
        |> Repo.update()
    end
  end

  defp outcome_to_license_type("F", :l1_eligible), do: :L2
  defp outcome_to_license_type("F", :l2_pass), do: :L2
  defp outcome_to_license_type("F", :l3_pass), do: :L3
  defp outcome_to_license_type("G", :l3_pass), do: :L3
  defp outcome_to_license_type(_, _), do: nil

  @doc """
  Auto-submits all non-submitted participants when an exam times out.

  Called server-side. Does not create empty answer rows for unanswered questions.
  """
  def timeout_exam(%Exam{} = exam) do
    exam = Repo.preload(exam, :participants)

    Enum.each(exam.participants, fn participant ->
      if participant.state not in ["submitted", "timed_out"] do
        participant
        |> ExamParticipant.changeset(%{
          state: "timed_out",
          submitted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
        })
        |> Repo.update!()
      end
    end)

    {:ok, exam} = update_exam_state(exam, "finished")
    score_exam(exam)
    broadcast(exam.id, {:exam_state_changed, exam})
    {:ok, exam}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc """
  Subscribes to broadcasts for the given exam.
  """
  def subscribe(exam_id) do
    Phoenix.PubSub.subscribe(Whistle.PubSub, "exam:#{exam_id}")
  end

  @doc """
  Broadcasts an event to all subscribers of the given exam.
  """
  def broadcast(exam_id, message) do
    Phoenix.PubSub.broadcast(Whistle.PubSub, "exam:#{exam_id}", message)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_and_select_questions(course_type, %{
         low: low_count,
         medium: medium_count,
         high: high_count
       }) do
    low_questions = fetch_questions_for(course_type, "low")
    medium_questions = fetch_questions_for(course_type, "medium")
    high_questions = fetch_questions_for(course_type, "high")

    with {:ok, low} <- pick_questions(low_questions, low_count, "low"),
         {:ok, medium} <- pick_questions(medium_questions, medium_count, "medium"),
         {:ok, high} <- pick_questions(high_questions, high_count, "high") do
      {:ok, low ++ medium ++ high}
    end
  end

  defp fetch_questions_for(course_type, difficulty) do
    from(q in Question,
      join: qct in QuestionCourseType,
      on: qct.question_id == q.id and qct.course_type == ^course_type,
      where: q.status == "active" and q.difficulty == ^difficulty,
      preload: :choices
    )
    |> Repo.all()
  end

  defp pick_questions(questions, count, difficulty) do
    available = length(questions)

    if available < count do
      {:error, {:not_enough_questions, difficulty, count, available}}
    else
      {:ok, Enum.take_random(questions, count)}
    end
  end

  defp snapshot_questions(exam, questions, now) do
    questions
    |> Enum.with_index(1)
    |> Enum.each(fn {question, position} ->
      {:ok, eq} =
        %ExamQuestion{}
        |> ExamQuestion.changeset(%{
          exam_id: exam.id,
          source_question_id: question.id,
          position: position,
          type: question.type,
          difficulty: question.difficulty,
          body_markdown: question.body_markdown,
          explanation_markdown: question.explanation_markdown,
          scoring_mode: question.scoring_mode,
          points: question.points || 1,
          created_at: now
        })
        |> Repo.insert()

      question.choices
      |> Enum.each(fn choice ->
        %ExamQuestionChoice{}
        |> ExamQuestionChoice.changeset(%{
          exam_question_id: eq.id,
          source_question_choice_id: choice.id,
          body_markdown: choice.body_markdown,
          position: choice.position,
          is_correct: choice.is_correct,
          created_at: now
        })
        |> Repo.insert!()
      end)
    end)
  end

  defp create_exam_participants(exam, user_ids, now) do
    Enum.each(user_ids, fn user_id ->
      %ExamParticipant{}
      |> ExamParticipant.changeset(%{
        exam_id: exam.id,
        user_id: user_id,
        state: "waiting"
      })
      |> Ecto.Changeset.put_change(:created_at, now)
      |> Repo.insert!()
    end)
  end
end
