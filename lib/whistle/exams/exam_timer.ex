defmodule Whistle.Exams.ExamTimer do
  @moduledoc """
  A simple GenServer that fires after duration_seconds and automatically
  times out the exam via `Whistle.Exams.timeout_exam/1`.

  Started when the instructor clicks "Start" and stopped when the exam
  is finished/canceled manually.
  """
  use GenServer

  alias Whistle.Exams

  @registry Whistle.Exams.ExamTimerRegistry

  def start_link({exam_id, duration_seconds}) do
    GenServer.start_link(__MODULE__, {exam_id, duration_seconds},
      name: via(exam_id)
    )
  end

  def start_timer(exam_id, duration_seconds) do
    DynamicSupervisor.start_child(
      Whistle.Exams.ExamTimerSupervisor,
      {__MODULE__, {exam_id, duration_seconds}}
    )
  end

  def stop_timer(exam_id) do
    case Registry.lookup(@registry, exam_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Whistle.Exams.ExamTimerSupervisor, pid)
      [] -> :ok
    end
  end

  @impl true
  def init({exam_id, duration_seconds}) do
    ms = duration_seconds * 1_000
    Process.send_after(self(), :timeout, ms)
    {:ok, %{exam_id: exam_id}}
  end

  @impl true
  def handle_info(:timeout, %{exam_id: exam_id} = state) do
    exam = Exams.get_exam!(exam_id)

    if exam.state == "running" do
      Exams.timeout_exam(exam)
    end

    {:stop, :normal, state}
  end

  defp via(exam_id) do
    {:via, Registry, {@registry, exam_id}}
  end
end
