defmodule WhistleWeb.RegistrationLive do
  alias Whistle.Registrations
  alias Whistle.Seasons
  alias Whistle.Courses
  alias Whistle.Accounts
  alias Whistle.Accounts.Role
  use WhistleWeb, :live_view
  require Logger

  on_mount WhistleWeb.UserAuthLive

  def mount(_params, _session, socket) do
    subscribe()

    user = socket.assigns.current_user
    season = Seasons.get_current_season()
    is_open = Seasons.is_registration_opened(season)
    courses = if season, do: load_courses(season.id), else: []

    # Load club members for admins
    club_members =
      if Role.can_manage_club_users?(user) do
        Accounts.list_manageable_users(user)
      else
        []
      end

    # Load existing registrations for the current user
    existing_registrations = load_existing_registrations(user, season)

    start_at = if season, do: season.start_registration, else: nil
    is_registration_passed = is_registration_passed?(season)

    {:ok,
     socket
     |> assign(:courses_by_date, group_courses_by_date(courses))
     |> assign(:is_open, is_open)
     |> assign(:season, season)
     |> assign(:start_at, start_at)
     |> assign(:is_registration_passed, is_registration_passed)
     |> assign(:selected_courses, MapSet.new())
     |> assign(:club_members, club_members)
     |> assign(:selected_member_id, nil)
     |> assign(:is_admin, Role.can_manage_club_users?(user))
     |> assign(:existing_registrations, existing_registrations)}
  end

  def handle_info({:course_updated, _course_id}, socket) do
    # Reload courses and existing registrations when someone registers
    user = socket.assigns.current_user
    season = socket.assigns.season

    # Determine which user's registrations to show
    target_user =
      if socket.assigns.selected_member_id do
        Accounts.get_user!(socket.assigns.selected_member_id)
      else
        user
      end

    courses = if season, do: load_courses(season.id), else: []
    existing_registrations = load_existing_registrations(target_user, season)

    {:noreply,
     socket
     |> assign(:courses_by_date, group_courses_by_date(courses))
     |> assign(:existing_registrations, existing_registrations)}
  end

  def handle_event("toggle_course", %{"course-id" => course_id_str}, socket) do
    course_id = String.to_integer(course_id_str)
    selected = socket.assigns.selected_courses

    new_selected =
      if MapSet.member?(selected, course_id) do
        MapSet.delete(selected, course_id)
      else
        MapSet.put(selected, course_id)
      end

    {:noreply, assign(socket, :selected_courses, new_selected)}
  end

  def handle_event("select_member", %{"member_id" => ""}, socket) do
    user = socket.assigns.current_user
    season = socket.assigns.season
    existing_registrations = load_existing_registrations(user, season)

    {:noreply,
     socket
     |> assign(:selected_member_id, nil)
     |> assign(:existing_registrations, existing_registrations)}
  end

  def handle_event("select_member", %{"member_id" => member_id}, socket) do
    member = Accounts.get_user!(String.to_integer(member_id))
    season = socket.assigns.season
    existing_registrations = load_existing_registrations(member, season)

    {:noreply,
     socket
     |> assign(:selected_member_id, String.to_integer(member_id))
     |> assign(:existing_registrations, existing_registrations)}
  end

  def handle_event("enroll", _params, socket) do
    user = socket.assigns.current_user
    selected_course_ids = MapSet.to_list(socket.assigns.selected_courses)

    # Determine who to enroll
    target_user =
      if socket.assigns.selected_member_id do
        Accounts.get_user!(socket.assigns.selected_member_id)
      else
        user
      end

    # Get actual Course structs (not CourseView) for the registration logic
    selected_courses =
      Enum.map(selected_course_ids, fn course_id ->
        Courses.get_course!(course_id)
      end)

    # Enroll using the business logic
    registered_by = if target_user.id != user.id, do: user.id, else: nil
    results = Registrations.enroll(target_user, selected_courses, registered_by)

    # Handle results
    {successes, errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    socket =
      Enum.reduce(successes, socket, fn {:ok, _reg}, acc ->
        put_flash(acc, :info, "Erfolgreich angemeldet!")
      end)

    socket =
      Enum.reduce(errors, socket, fn {:error, error}, acc ->
        error_msg = format_error(error)
        put_flash(acc, :error, error_msg)
      end)

    # Broadcast update and clear selection
    Enum.each(selected_course_ids, fn course_id ->
      broadcast({:course_updated, course_id})
    end)

    {:noreply,
     socket
     |> assign(:selected_courses, MapSet.new())
     |> assign(:selected_member_id, nil)}
  end

  defp load_courses(season_id) do
    Courses.list_courses_view()
    |> Enum.filter(&(&1.season_id == season_id))
  end

  defp load_existing_registrations(user, season) do
    if season do
      Registrations.list_registrations_view(season_id: season.id)
      |> Enum.filter(&(&1.user_id == user.id))
      |> MapSet.new(& &1.course_id)
    else
      MapSet.new()
    end
  end

  defp group_courses_by_date(courses) do
    courses
    |> Enum.group_by(& &1.date)
    |> Enum.sort_by(fn {date, _} -> date end, {:asc, Date})
    |> Enum.reject(fn {date, _} -> is_nil(date) end)
  end

  defp get_selected_course_types(courses_by_date, selected_courses) do
    courses_by_date
    |> Enum.flat_map(fn {_date, courses} -> courses end)
    |> Enum.filter(fn c -> MapSet.member?(selected_courses, c.id) end)
    |> Enum.map(& &1.type)
    |> MapSet.new()
  end

  defp get_existing_course_types(courses_by_date, existing_registrations) do
    courses_by_date
    |> Enum.flat_map(fn {_date, courses} -> courses end)
    |> Enum.filter(fn c -> MapSet.member?(existing_registrations, c.id) end)
    |> Enum.map(& &1.type)
    |> MapSet.new()
  end

  defp course_disabled?(course, selected_courses, courses_by_date, existing_registrations) do
    # If course is already registered, it's disabled (locked in)
    already_registered = MapSet.member?(existing_registrations, course.id)

    # If course is selected (but not already registered), it's not disabled
    if MapSet.member?(selected_courses, course.id) and not already_registered do
      false
    else
      # Check total count: existing + selected courses
      total_count = MapSet.size(existing_registrations) + MapSet.size(selected_courses)

      # If already at 2 courses total and this isn't already registered, disable it
      if total_count >= 2 and not already_registered do
        true
      else
        # Only check type conflicts for F, J, G courses
        if course.type in ["F", "J", "G"] and not already_registered do
          # Get types from both selected and existing registrations
          selected_types = get_selected_course_types(courses_by_date, selected_courses)
          existing_types = get_existing_course_types(courses_by_date, existing_registrations)
          all_types = MapSet.union(selected_types, existing_types)
          MapSet.member?(all_types, course.type)
        else
          # Already registered courses are disabled
          already_registered
        end
      end
    end
  end

  defp type_badge_color(type) do
    case type do
      "F" -> "bg-blue-100 text-blue-800 border-blue-300"
      "J" -> "bg-green-100 text-green-800 border-green-300"
      "G" -> "bg-purple-100 text-purple-800 border-purple-300"
      _ -> "bg-gray-100 text-gray-800 border-gray-300"
    end
  end

  defp format_error({:only_two_courses_allowed, count}) do
    "Du kannst maximal 2 Kurse belegen. Du bist bereits für #{count} Kurse angemeldet."
  end

  defp format_error({:already_registered, _user_id, _course_id}) do
    "Du bist bereits für diesen Kurs angemeldet."
  end

  defp format_error({:not_available, course}) do
    "Kurs '#{course.name}' ist ausgebucht."
  end

  defp format_error({:not_allowed, course}) do
    "Anmeldung für Kurs '#{course.name}' nicht erlaubt (Limit erreicht)."
  end

  defp format_error(_), do: "Ein Fehler ist aufgetreten."

  defp is_registration_passed?(season) do
    if season && season.end_registration do
      today = Whistle.Timezone.today_local()
      end_date = NaiveDateTime.to_date(season.end_registration)
      Date.compare(today, end_date) == :gt
    else
      false
    end
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h2 class="text-2xl font-bold">Kursanmeldung</h2>

      <%= if !@is_open && @is_registration_passed do %>
        <div class="rounded-lg border border-yellow-200 bg-yellow-50 p-4 text-yellow-800">
          Die Kursnameldung ist beendet. Sie wird im nächsten Jahr wieder freigegeben.
        </div>
      <% end %>

      <%= if !@is_open && !@is_registration_passed && @start_at do %>
        <div class="rounded-lg border border-yellow-200 bg-yellow-50 p-4 text-yellow-800">
          Leider ist die Kursnameldung noch nicht freigegeben. Sie wird am {Calendar.strftime(
            @start_at,
            "%d.%m.%Y"
          )} geöffnet.
        </div>
      <% end %>

      <%= if !@is_open && !@is_registration_passed && !@start_at do %>
        <div class="rounded-lg border border-yellow-200 bg-yellow-50 p-4 text-yellow-800">
          Leider ist die Kursnameldung noch nicht freigegeben und ein Termin steht noch nicht fest.
        </div>
      <% end %>

      <%= if @is_open do %>
        <.form for={%{}} phx-submit="enroll">
          <%= if @is_admin && @club_members != [] do %>
            <div class="mb-6">
              <label class="block text-sm font-medium mb-2">Mitglied (optional)</label>
              <select
                name="member_id"
                phx-change="select_member"
                class="w-full rounded-lg border border-gray-300 px-3 py-2"
              >
                <option value="">-- Für mich selbst --</option>
                <%= for member <- @club_members do %>
                  <option value={member.id} selected={@selected_member_id == member.id}>
                    {member.username} ({member.email})
                  </option>
                <% end %>
              </select>
            </div>
          <% end %>

          <%= if @courses_by_date == [] do %>
            <div class="text-center py-12 text-zinc-500">
              <.icon name="hero-calendar" class="h-16 w-16 mx-auto mb-4 opacity-50" />
              <p>Keine Kurse verfügbar.</p>
            </div>
          <% else %>
            <%= for {date, courses} <- @courses_by_date do %>
              <div class="mb-8">
                <h3 class="font-semibold mb-4">
                  {Calendar.strftime(date, "%d. %B %Y")}
                </h3>

                <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                  <%= for course <- courses do %>
                    <% already_registered = MapSet.member?(@existing_registrations, course.id) %>
                    <% disabled =
                      course_disabled?(
                        course,
                        @selected_courses,
                        @courses_by_date,
                        @existing_registrations
                      ) %>
                    <% selected = MapSet.member?(@selected_courses, course.id) or already_registered %>

                    <div
                      class={"rounded-lg border p-4 shadow-sm cursor-pointer transition-all relative " <>
                             if(disabled, do: "bg-zinc-100 opacity-50 cursor-not-allowed", else: "bg-white hover:shadow-md") <>
                             if(selected, do: " ring-2 ring-blue-500", else: "")}
                      phx-click={unless disabled, do: "toggle_course"}
                      phx-value-course-id={course.id}
                    >
                      <div class="flex gap-3">
                        <div class="flex-1">
                          <h4 class="font-bold text-base mb-3">{course.name}</h4>

                          <div class="text-sm text-zinc-600 space-y-1">
                            <div class="flex items-center gap-2">
                              <.icon name="hero-map-pin" class="h-4 w-4" />
                              {course.organizer_name}
                            </div>
                            <div class="flex items-center gap-2">
                              <.icon name="hero-users" class="h-4 w-4" />
                              {course.participants} / {course.max_participants}
                            </div>
                          </div>
                        </div>

                        <div class="flex flex-col items-center gap-2">
                          <input
                            type="checkbox"
                            checked={selected}
                            disabled={disabled}
                            class="h-4 w-4 rounded border-gray-300 flex-shrink-0"
                            phx-click={unless disabled, do: "toggle_course"}
                            phx-value-course-id={course.id}
                          />
                          <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border " <> type_badge_color(course.type)}>
                            {course.type}
                          </span>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <div class="flex justify-end mt-6">
              <.button
                type="submit"
                disabled={MapSet.size(@selected_courses) == 0}
                class="px-6 py-2"
              >
                Anmelden ({MapSet.size(@selected_courses)} Kurse)
              </.button>
            </div>
          <% end %>
        </.form>
      <% end %>
    </div>
    """
  end

  defp subscribe() do
    Phoenix.PubSub.subscribe(Whistle.PubSub, "registration")
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Whistle.PubSub, "registration", message)
  end
end
