defmodule WhistleWeb.CourseEditLive do
  use WhistleWeb, :live_view

  alias Whistle.Accounts.Role
  alias Whistle.Clubs
  alias Whistle.Courses
  alias Whistle.Courses.Course
  alias Whistle.Exams
  alias Whistle.Registrations
  alias Whistle.Seasons

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    case parse_id(id) do
      {:ok, course_id} ->
        case Courses.get_course(course_id) do
          nil ->
            {:noreply, push_navigate(socket, to: ~p"/admin/courses")}

          course ->
            tab =
              case params["tab"] do
                t when t in ["kursdaten", "tests", "teilnehmer"] -> String.to_existing_atom(t)
                _ -> :kursdaten
              end

            {:noreply, socket |> assign_base(course) |> load_tab(tab)}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/admin/courses")}
    end
  end

  def handle_params(_params, _uri, socket) do
    current_season = Seasons.get_current_season()
    season_id = if current_season, do: current_season.id, else: nil

    {:noreply,
     socket
     |> assign(:course, nil)
     |> assign_course_form(Courses.change_course(%Course{season_id: season_id}))
     |> assign(:types, Course.available_types())
     |> assign(:clubs, get_club_options())
     |> assign(:seasons, get_season_options())
     |> assign_child_forms()
     |> assign(:tab, :kursdaten)
     |> assign(:course_dates, [])
     |> assign(:course_date_topics, [])
     |> assign(:exams, [])
     |> assign(:registrations, [])
     |> assign(:date_selections_by_registration, %{})}
  end

  @impl true
  def handle_event("validate", %{"course" => params}, socket) do
    course = socket.assigns.course || %Course{}
    changeset = Courses.change_course(course, params)
    {:noreply, assign_course_form(socket, changeset)}
  end

  def handle_event("create", %{"course" => params}, socket) do
    case Courses.create_course(params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, "Kurs wurde erfolgreich erstellt.")
         |> push_navigate(to: ~p"/admin/courses/#{course}/edit")}

      {:error, changeset} ->
        {:noreply, assign_course_form(socket, changeset)}
    end
  end

  def handle_event("save", %{"course" => params}, socket) do
    course = socket.assigns.course

    case Courses.update_course(course, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:course, updated)
         |> assign_course_form(Courses.change_course(updated))
         |> put_flash(:info, "Kurs wurde erfolgreich aktualisiert.")}

      {:error, changeset} ->
        {:noreply, assign_course_form(socket, changeset)}
    end
  end

  def handle_event("release", _params, socket) do
    course = socket.assigns.course

    case Courses.release_course(course) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:course, updated)
         |> assign_course_form(Courses.change_course(updated))
         |> put_flash(:info, "Der Kurs #{updated.name} wurde erfolgreich freigegeben.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Kurs konnte nicht freigegeben werden.")}
    end
  end

  def handle_event("release_exam_solutions", _params, socket) do
    case Courses.release_exam_solutions(socket.assigns.course) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:course, updated)
         |> assign_course_form(Courses.change_course(updated))
         |> put_flash(:info, "Lösungen wurden für diesen Kurs freigegeben.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Lösungen konnten nicht freigegeben werden.")}
    end
  end

  def handle_event("hide_exam_solutions", _params, socket) do
    case Courses.hide_exam_solutions(socket.assigns.course) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:course, updated)
         |> assign_course_form(Courses.change_course(updated))
         |> put_flash(:info, "Lösungen wurden für diesen Kurs verborgen.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Lösungen konnten nicht verborgen werden.")}
    end
  end

  def handle_event("delete", _params, socket) do
    course = socket.assigns.course

    case Courses.delete_course(course) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Kurs wurde erfolgreich gelöscht.")
         |> push_navigate(to: ~p"/admin/courses")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Kurs konnte nicht gelöscht werden.")}
    end
  end

  def handle_event("add_date", %{"course_date" => params}, socket) do
    case Courses.create_course_date(params) do
      {:ok, _} ->
        course = socket.assigns.course
        course_dates = Courses.list_course_dates(course)
        {:noreply, assign(socket, :course_dates, course_dates)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Termin konnte nicht hinzugefügt werden.")}
    end
  end

  def handle_event("delete_date", %{"id" => id}, socket) do
    case parse_id(id) do
      {:ok, date_id} ->
        course_dates = socket.assigns.course_dates
        date = Enum.find(course_dates, &(&1.id == date_id))

        if date do
          Courses.delete_course_date(date)
          course = socket.assigns.course
          {:noreply, assign(socket, :course_dates, Courses.list_course_dates(course))}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_topic", %{"course_date_topic" => params}, socket) do
    case Courses.create_course_date_topic(params) do
      {:ok, _} ->
        course = socket.assigns.course
        {:noreply, assign(socket, :course_date_topics, Courses.list_course_date_topics(course))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Thema konnte nicht angelegt werden.")}
    end
  end

  def handle_event("delete_topic", %{"id" => id}, socket) do
    case parse_id(id) do
      {:ok, topic_id} ->
        topics = socket.assigns.course_date_topics
        topic = Enum.find(topics, &(&1.id == topic_id))

        if topic do
          Courses.delete_course_date_topic(topic)
          course = socket.assigns.course

          {:noreply,
           socket
           |> assign(:course_date_topics, Courses.list_course_date_topics(course))
           |> assign(:course_dates, Courses.list_course_dates(course))}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_exam", %{"exam-id" => exam_id}, socket) do
    case parse_id(exam_id) do
      {:ok, id} ->
        exam = Exams.get_exam(id)

        if exam && exam.course_id == socket.assigns.course.id &&
             exam.state in ["waiting_room", "running", "paused"] do
          Exams.ExamTimer.stop_timer(exam.id)
          {:ok, updated} = Exams.update_exam_state(exam, "canceled")
          Exams.broadcast(updated.id, {:exam_state_changed, updated})
          course = socket.assigns.course

          {:noreply,
           socket
           |> assign(:exams, Exams.list_exams(course_id: course.id))
           |> put_flash(:info, "Test wurde abgebrochen.")}
        else
          {:noreply, put_flash(socket, :error, "Test konnte nicht abgebrochen werden.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("sign_out_participant", %{"user-id" => user_id_str}, socket) do
    course = socket.assigns.course
    admin = socket.assigns.current_user

    case parse_id(user_id_str) do
      {:ok, user_id} ->
        case Whistle.Registrations.sign_out(course.id, user_id, admin.id) do
          {:ok, _} ->
            date_selections =
              if course.online,
                do: Courses.list_date_selections_for_course(course),
                else: %{}

            registrations =
              Registrations.list_registrations_view(include_unenrolled: true)
              |> Enum.filter(&(&1.course_id == course.id))
              |> then(fn regs ->
                if course.online do
                  Enum.sort_by(regs, fn reg ->
                    dates = Map.get(date_selections, reg.registration_id, [])
                    first_date = dates |> Enum.sort_by(& &1.date) |> List.first()

                    if first_date,
                      do: {first_date.date, first_date.time},
                      else: {~D[9999-01-01], ~T[00:00:00]}
                  end)
                else
                  regs
                end
              end)

            {:noreply,
             socket
             |> assign(:registrations, registrations)
             |> assign(:date_selections_by_registration, date_selections)
             |> put_flash(:info, "Der Teilnehmer wurde erfolgreich abgemeldet.")}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Registrierung nicht gefunden.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Teilnehmer konnte nicht abgemeldet werden.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp assign_base(socket, course) do
    socket
    |> assign(:course, course)
    |> assign_course_form(Courses.change_course(course))
    |> assign(:types, Course.available_types())
    |> assign(:clubs, get_club_options())
    |> assign(:seasons, get_season_options())
    |> assign_child_forms()
    |> assign(:tab, :kursdaten)
    |> assign(:course_dates, [])
    |> assign(:course_date_topics, [])
    |> assign(:exams, [])
    |> assign(:registrations, [])
    |> assign(:date_selections_by_registration, %{})
  end

  defp load_tab(socket, :kursdaten) do
    course = socket.assigns.course

    socket
    |> assign(:tab, :kursdaten)
    |> assign(:course_dates, Courses.list_course_dates(course))
    |> assign(:course_date_topics, Courses.list_course_date_topics(course))
    |> assign(:exams, [])
    |> assign(:registrations, [])
    |> assign(:date_selections_by_registration, %{})
  end

  defp load_tab(socket, :tests) do
    course = socket.assigns.course

    socket
    |> assign(:tab, :tests)
    |> assign(:exams, Exams.list_exams(course_id: course.id))
    |> assign(:course_dates, [])
    |> assign(:course_date_topics, [])
    |> assign(:registrations, [])
    |> assign(:date_selections_by_registration, %{})
  end

  defp load_tab(socket, :teilnehmer) do
    course = socket.assigns.course

    registrations =
      Registrations.list_registrations_view(include_unenrolled: true)
      |> Enum.filter(&(&1.course_id == course.id))

    date_selections =
      if course.online,
        do: Courses.list_date_selections_for_course(course),
        else: %{}

    registrations =
      if course.online do
        Enum.sort_by(registrations, fn reg ->
          dates = Map.get(date_selections, reg.registration_id, [])
          first_date = dates |> Enum.sort_by(& &1.date) |> List.first()

          if first_date,
            do: {first_date.date, first_date.time},
            else: {~D[9999-01-01], ~T[00:00:00]}
        end)
      else
        registrations
      end

    socket
    |> assign(:tab, :teilnehmer)
    |> assign(:registrations, registrations)
    |> assign(:date_selections_by_registration, date_selections)
    |> assign(:course_dates, [])
    |> assign(:course_date_topics, [])
    |> assign(:exams, [])
  end

  defp get_club_options do
    Clubs.list_clubs() |> Enum.map(&{&1.name, &1.id})
  end

  defp get_season_options do
    Seasons.list_seasons() |> Enum.map(&{"Saison #{&1.year}", &1.id})
  end

  defp assign_course_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_child_forms(socket) do
    socket
    |> assign(:course_date_form, to_form(%{}, as: :course_date))
    |> assign(:course_date_topic_form, to_form(%{}, as: :course_date_topic))
  end

  defp course_form_type?(form, type), do: form[:type].value == type

  defp course_form_online?(form) do
    form[:online].value in [true, "true", "on", "1"]
  end

  defp parse_id(id), do: WhistleWeb.ControllerHelpers.parse_id(id)

  @impl true
  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item navigate={~p"/admin/courses"}>Kurse</:item>
      <:item :if={@course}>{@course.name}</:item>
      <:item :if={!@course}>Neuer Kurs</:item>
    </.breadcrumbs>

    <.header>
      {if @course, do: @course.name, else: "Neuer Kurs"}
      <:subtitle :if={!@course}>
        Verwende dieses Formular, um Kurse zu verwalten und anzulegen.
      </:subtitle>
    </.header>

    <%= if @course do %>
      <.tabs>
        <:tab
          label="Kursdaten"
          patch={~p"/admin/courses/#{@course}/edit?tab=kursdaten"}
          active={@tab == :kursdaten}
        />
        <:tab
          label="Tests"
          patch={~p"/admin/courses/#{@course}/edit?tab=tests"}
          active={@tab == :tests}
        />
        <:tab
          label="Teilnehmer"
          patch={~p"/admin/courses/#{@course}/edit?tab=teilnehmer"}
          active={@tab == :teilnehmer}
        />
      </.tabs>
    <% end %>

    <%= if !@course || @tab == :kursdaten do %>
      <.form
        for={@form}
        id="course-form"
        phx-change="validate"
        phx-submit={if @course, do: "save", else: "create"}
      >
        <div class="flex flex-col gap-2">
          <.error :if={@form.source.action}>
            Ups, es ist ein Fehler aufgetreten. Bitte prüfe die Fehler weiter unten.
          </.error>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input
            field={@form[:type]}
            options={@types}
            prompt="Bitte wähle den Typen"
            type="select"
            label="Typ"
          />
          <%= if course_form_type?(@form, "F") do %>
            <.input field={@form[:online]} type="checkbox" label="Online-Kurs" />
          <% end %>
          <.input
            field={@form[:season_id]}
            options={@seasons}
            prompt="Wähle eine Saison"
            type="select"
            label="Saison"
            required
          />
          <%= if !course_form_online?(@form) && (!@course || !@course.online) do %>
            <.input field={@form[:date]} type="date" label="Datum" />
            <.input
              field={@form[:organizer_id]}
              options={@clubs}
              prompt="Kein Ausrichter"
              type="select"
              label="Ausrichter"
            />
          <% end %>
          <div class="flex flex-row gap-4 w-full">
            <div class="flex-1">
              <.input field={@form[:max_participants]} type="number" label="Maximale Teilnehmer" />
            </div>
            <div class="flex-1">
              <.input
                field={@form[:max_per_club]}
                type="number"
                label="Maximale Teilnehmer pro Verein"
              />
            </div>
            <%= if !course_form_online?(@form) && (!@course || !@course.online) do %>
              <div class="flex-1">
                <.input
                  field={@form[:max_organizer_participants]}
                  type="number"
                  label="Maximale Teilnehmer für Ausrichter"
                />
              </div>
            <% end %>
          </div>
          <div class="mt-2 flex items-center gap-4">
            <.button type="submit">{if @course, do: "Speichern", else: "Erstellen"}</.button>
            <.action_link
              :if={@course && is_nil(@course.released_at)}
              phx-click="release"
              data-confirm="Möchtest du diesen Kurs wirklich freigeben?"
              tone={:primary}
              href="#"
            >
              Freigeben
            </.action_link>
            <.action_link
              :if={@course && Role.can_delete?(@current_user)}
              phx-click="delete"
              data-confirm="Bist du dir sicher?"
              tone={:danger}
              href="#"
            >
              Löschen
            </.action_link>
          </div>
        </div>
      </.form>

      <%= if @course && @course.online do %>
        <div class="mt-8">
          <h3 class="text-lg font-semibold mb-4">Termine</h3>

          <div class="mb-6">
            <h4 class="text-sm font-medium text-base-content/70 mb-2 uppercase tracking-wide">
              Pflichttermine
            </h4>
            <div class="space-y-2 mb-3">
              <%= for date <- Enum.filter(@course_dates, &(&1.kind == :mandatory)) do %>
                <div class="flex items-center justify-between gap-4 rounded-xl border border-base-200 bg-base-100 shadow-sm px-4 py-3">
                  <div class="text-sm font-medium">
                    {Calendar.strftime(date.date, "%d.%m.%Y")} &middot; {Time.to_string(date.time)
                    |> String.slice(0, 5)} Uhr
                  </div>
                  <.action_link
                    phx-click="delete_date"
                    phx-value-id={date.id}
                    data-confirm="Termin wirklich löschen?"
                    tone={:danger}
                    href="#"
                  >
                    Löschen
                  </.action_link>
                </div>
              <% end %>
            </div>
            <.form
              for={@course_date_form}
              id="mandatory-course-date-form"
              phx-submit="add_date"
              class="flex items-end gap-2"
            >
              <.input
                field={@course_date_form[:kind]}
                id="mandatory-course-date-kind"
                type="hidden"
                value="mandatory"
              />
              <.input
                field={@course_date_form[:course_id]}
                id="mandatory-course-date-course-id"
                type="hidden"
                value={@course.id}
              />
              <div>
                <.input
                  field={@course_date_form[:date]}
                  id="mandatory-course-date-date"
                  type="date"
                  label="Datum"
                  required
                />
              </div>
              <div>
                <.input
                  field={@course_date_form[:time]}
                  id="mandatory-course-date-time"
                  type="time"
                  label="Uhrzeit"
                  required
                />
              </div>
              <.button type="submit">Hinzufügen</.button>
            </.form>
          </div>

          <div>
            <h4 class="text-sm font-medium text-base-content/70 mb-2 uppercase tracking-wide">
              Wahlpflichttermine
            </h4>

            <%= for topic <- @course_date_topics do %>
              <div class="mb-4 rounded-xl border border-base-200 bg-base-50 p-4">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-sm font-medium">{topic.name}</span>
                  <.action_link
                    phx-click="delete_topic"
                    phx-value-id={topic.id}
                    data-confirm={"Thema '#{topic.name}' und alle zugehörigen Termine löschen?"}
                    tone={:danger}
                    href="#"
                  >
                    Löschen
                  </.action_link>
                </div>
                <div class="space-y-2 mb-2">
                  <%= for date <- Enum.filter(@course_dates, &(&1.kind == :elective && &1.course_date_topic_id == topic.id)) do %>
                    <div class="flex items-center justify-between gap-4 rounded-lg border border-base-200 bg-base-100 px-3 py-2">
                      <div class="text-sm">
                        {Calendar.strftime(date.date, "%d.%m.%Y")} &middot; {Time.to_string(date.time)
                        |> String.slice(0, 5)} Uhr
                      </div>
                      <.action_link
                        phx-click="delete_date"
                        phx-value-id={date.id}
                        data-confirm="Termin wirklich löschen?"
                        tone={:danger}
                        href="#"
                      >
                        Löschen
                      </.action_link>
                    </div>
                  <% end %>
                </div>
                <.form
                  for={@course_date_form}
                  id={"elective-course-date-form-#{topic.id}"}
                  phx-submit="add_date"
                  class="flex items-end gap-2"
                >
                  <.input
                    field={@course_date_form[:kind]}
                    id={"elective-course-date-kind-#{topic.id}"}
                    type="hidden"
                    value="elective"
                  />
                  <.input
                    field={@course_date_form[:course_id]}
                    id={"elective-course-date-course-id-#{topic.id}"}
                    type="hidden"
                    value={@course.id}
                  />
                  <.input
                    field={@course_date_form[:course_date_topic_id]}
                    id={"elective-course-date-topic-id-#{topic.id}"}
                    type="hidden"
                    value={topic.id}
                  />
                  <div>
                    <.input
                      field={@course_date_form[:date]}
                      id={"elective-course-date-date-#{topic.id}"}
                      type="date"
                      label="Datum"
                      required
                    />
                  </div>
                  <div>
                    <.input
                      field={@course_date_form[:time]}
                      id={"elective-course-date-time-#{topic.id}"}
                      type="time"
                      label="Uhrzeit"
                      required
                    />
                  </div>
                  <.button type="submit">Hinzufügen</.button>
                </.form>
              </div>
            <% end %>

            <.form
              for={@course_date_topic_form}
              id="course-date-topic-form"
              phx-submit="add_topic"
              class="flex items-end gap-2 mt-2"
            >
              <.input
                field={@course_date_topic_form[:course_id]}
                id="course-date-topic-course-id"
                type="hidden"
                value={@course.id}
              />
              <div class="flex-1">
                <.input
                  field={@course_date_topic_form[:name]}
                  id="course-date-topic-name"
                  type="text"
                  label="Neues Thema"
                  required
                  placeholder="z.B. Zitronentarte"
                />
              </div>
              <.button type="submit">Thema anlegen</.button>
            </.form>
          </div>
        </div>
      <% end %>
    <% end %>

    <%= if @tab == :tests do %>
      <div
        id="exam-solutions-release-panel"
        class="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-base-200 bg-base-100 px-4 py-3 shadow-sm"
      >
        <div>
          <p class="text-sm font-medium text-base-content">Lösungseinsicht</p>
          <p class="mt-0.5 text-xs text-base-content/55">
            <%= if @course.exam_solutions_released_at do %>
              Freigegeben am {Whistle.Timezone.format_local(
                @course.exam_solutions_released_at,
                "%d.%m.%Y %H:%M"
              )}
            <% else %>
              Noch nicht für Teilnehmende sichtbar.
            <% end %>
          </p>
        </div>
        <div class="flex items-center gap-2">
          <.button
            :if={is_nil(@course.exam_solutions_released_at)}
            id="release-exam-solutions-button"
            phx-click="release_exam_solutions"
            type="button"
          >
            Lösungen freigeben
          </.button>
          <.button
            :if={@course.exam_solutions_released_at}
            id="hide-exam-solutions-button"
            phx-click="hide_exam_solutions"
            type="button"
            data-confirm="Lösungen für Teilnehmende wieder verbergen?"
          >
            Lösungen verbergen
          </.button>
        </div>
      </div>

      <div class="flex justify-end mb-4">
        <.button navigate={~p"/admin/courses/#{@course}/exams/new"}>Test erstellen</.button>
      </div>
      <%= if Enum.empty?(@exams) do %>
        <p class="py-10 text-center text-sm text-base-content/50">
          Noch keine Tests für diesen Kurs.
        </p>
      <% else %>
        <div class="space-y-2">
          <%= for exam <- @exams do %>
            <div class="flex items-center gap-2 rounded-xl border border-base-200 bg-base-100 shadow-sm px-4 py-3">
              <.link
                navigate={~p"/admin/exams/#{exam}"}
                class="flex items-center justify-between gap-4 min-w-0 flex-1 transition-colors hover:opacity-70"
              >
                <div class="min-w-0 flex-1">
                  <div class="text-sm font-medium">{exam.course_type}</div>
                  <div class="mt-0.5 text-xs text-base-content/55">
                    {[
                      exam.state,
                      "#{exam.question_count} Fragen",
                      Calendar.strftime(exam.created_at, "%d.%m.%Y %H:%M")
                    ]
                    |> Enum.filter(& &1)
                    |> Enum.join(" · ")}
                  </div>
                </div>
                <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/30" />
              </.link>
              <.action_link
                :if={exam.state in ["waiting_room", "running", "paused"]}
                phx-click="cancel_exam"
                phx-value-exam-id={exam.id}
                data-confirm="Test wirklich abbrechen?"
                tone={:danger}
                href="#"
              >
                Abbrechen
              </.action_link>
            </div>
          <% end %>
        </div>
      <% end %>
    <% end %>

    <%= if @tab == :teilnehmer do %>
      <%= if Enum.empty?(@registrations) do %>
        <p class="py-10 text-center text-sm text-base-content/50">
          Noch keine Anmeldungen für diesen Kurs.
        </p>
      <% else %>
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-base-content/60">{length(@registrations)} Anmeldung(en)</p>
          <div class="flex items-center gap-2">
            <.button href={~p"/admin/courses/#{@course}/export"}>
              <.icon name="hero-arrow-down-tray" class="size-4" /> CSV
            </.button>
            <.button
              variant="primary"
              href={"mailto:?bcc=#{@registrations |> Enum.filter(fn r -> is_nil(r.unenrolled_at) end) |> Enum.map(& &1.user_email) |> Enum.join(";")}"}
            >
              <.icon name="hero-envelope" class="size-4" /> Mail an alle
            </.button>
          </div>
        </div>
        <div class="space-y-2">
          <%= for reg <- @registrations do %>
            <% selected_dates = Map.get(@date_selections_by_registration, reg.registration_id, []) %>
            <div class="flex items-center justify-between gap-4 rounded-xl border border-base-200 bg-base-100 shadow-sm px-4 py-3">
              <div class="min-w-0 flex-1">
                <div class="truncate text-sm font-medium">
                  {[reg.user_first_name, reg.user_last_name, reg.username && "(#{reg.username})"]
                  |> Enum.filter(& &1)
                  |> Enum.join(" ")}
                </div>
                <div class="mt-0.5 text-xs text-base-content/55">
                  <%= if reg.unenrolled_at do %>
                    <% datum = Calendar.strftime(reg.unenrolled_at, "%d.%m.%Y %H:%M") %>
                    <%= if reg.course_date &&
                          Date.compare(
                            Date.add(reg.course_date, -7),
                            NaiveDateTime.to_date(reg.unenrolled_at)
                          ) == :gt do %>
                      Abgemeldet {datum}
                      <span class="ml-1 text-error font-medium">
                        Abmeldung weniger als 7 Tage vor Kurs
                      </span>
                    <% else %>
                      Abgemeldet {datum}
                    <% end %>
                  <% else %>
                    {reg.user_email}
                  <% end %>
                </div>
                <%= if @course.online && is_nil(reg.unenrolled_at) && selected_dates != [] do %>
                  <div class="mt-1 text-xs text-base-content/70">
                    {selected_dates
                    |> Enum.sort_by(& &1.kind)
                    |> Enum.map(fn d ->
                      "#{Calendar.strftime(d.date, "%d.%m.%Y")} #{Time.to_string(d.time) |> String.slice(0, 5)} Uhr"
                    end)
                    |> Enum.join(" · ")}
                  </div>
                <% end %>
              </div>
              <% days_until =
                reg.course_date && Date.diff(reg.course_date, Whistle.Timezone.today_local()) %>
              <% short_notice = days_until != nil && days_until >= 0 && days_until < 7 %>
              <.action_link
                :if={
                  is_nil(reg.unenrolled_at) &&
                    Role.can_access_course_area?(@current_user)
                }
                phx-click="sign_out_participant"
                phx-value-user-id={reg.user_id}
                data-confirm={
                  if short_notice,
                    do:
                      "Achtung: Der Kurs findet in weniger als 7 Tagen statt. Bei kurzfristiger Abmeldung wird eine Gebühr fällig. Trotzdem abmelden?",
                    else: "Möchtest du diesen Teilnehmer wirklich abmelden?"
                }
                tone={:danger}
                href="#"
              >
                Abmelden
              </.action_link>
            </div>
          <% end %>
        </div>
      <% end %>
    <% end %>
    """
  end
end
