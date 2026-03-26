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
  Gets a single question with preloaded choices and course type assignments.
  """
  def get_question_with_details!(id) do
    Question
    |> Repo.get!(id)
    |> Repo.preload([:choices, :course_type_assignments])
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
  def set_question_course_types(%Question{} = question, course_types) when is_list(course_types) do
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
  Gets an exam with participants and questions preloaded.
  """
  def get_exam_with_details!(id) do
    Exam
    |> Repo.get!(id)
    |> Repo.preload([:participants, questions: :choices])
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
    title = Keyword.get(opts, :title, "Exam #{course.name}")
    show_countdown = Keyword.get(opts, :show_countdown_to_participants, false)

    Repo.transaction(fn ->
      distribution = get_distribution_for_course_type(course.type)

      question_count = distribution.question_count
      counts = calculate_difficulty_counts(question_count, distribution)

      questions = load_and_select_questions(course.type, counts)

      case questions do
        {:error, reason} -> Repo.rollback(reason)
        {:ok, selected_questions} ->
          now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

          {:ok, exam} =
            %Exam{}
            |> Exam.changeset(%{
              course_id: course.id,
              course_type: course.type,
              title: title,
              state: "waiting_room",
              question_count: question_count,
              duration_seconds: distribution.duration_seconds,
              pass_percentage: distribution.pass_percentage,
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
              answer |> Repo.preload(:answer_choices) |> Map.get(:answer_choices) |> Enum.map(& &1.exam_question_choice_id)
            else
              []
            end

          {question, choice_ids}
        end)

      result =
        Whistle.Exams.Scoring.compute_total(
          question_answer_pairs,
          exam.pass_percentage
        )

      license_decision = if result.passed, do: "granted", else: "denied"

      participant
      |> ExamParticipant.changeset(%{
        score: result.score,
        max_score: result.max_score,
        passed: result.passed,
        license_decision: license_decision
      })
      |> Repo.update!()

      if result.passed do
        issue_provisional_license(participant, exam)
      end
    end)

    broadcast(exam.id, {:exam_scored, exam})
    :ok
  end

  @doc """
  Issues a provisional license for a participant who passed.

  Uses the current season and a randomly generated unique 7-digit number.
  If no current season exists, skips license creation.
  """
  def issue_provisional_license(participant, exam) do
    season = Whistle.Seasons.get_current_season()

    if season do
      license_type = course_type_to_license_type(exam.course_type)

      issue_license_with_retry(participant.user_id, season.id, license_type, 5)
    end
  end

  defp issue_license_with_retry(_user_id, _season_id, _license_type, 0), do: {:error, :max_retries}

  defp issue_license_with_retry(user_id, season_id, license_type, retries) do
    number = :rand.uniform(9_000_000) + 1_000_000

    case Whistle.Repo.insert(
           Whistle.Accounts.License.changeset(%Whistle.Accounts.License{}, %{
             number: number,
             type: license_type,
             season_id: season_id,
             user_id: user_id,
             created_by: user_id
           })
         ) do
      {:ok, license} ->
        {:ok, license}

      {:error, %Ecto.Changeset{errors: [number: {_, [{:constraint, :unique} | _]}]}} ->
        issue_license_with_retry(user_id, season_id, license_type, retries - 1)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp course_type_to_license_type("F"), do: :N1
  defp course_type_to_license_type("J"), do: :LJ
  defp course_type_to_license_type("G"), do: :N1
  defp course_type_to_license_type(_), do: :N1

  @doc """
  Auto-submits all non-submitted participants when an exam times out.

  Called server-side. Does not create empty answer rows for unanswered questions.
  """
  def timeout_exam(%Exam{} = exam) do
    exam = Repo.preload(exam, :participants)

    Enum.each(exam.participants, fn participant ->
      if participant.state not in ["submitted", "timed_out"] do
        participant
        |> ExamParticipant.changeset(%{state: "timed_out", submitted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)})
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

  defp load_and_select_questions(course_type, %{low: low_count, medium: medium_count, high: high_count}) do
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
          points: 1,
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
