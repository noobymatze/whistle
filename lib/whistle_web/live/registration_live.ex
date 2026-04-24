defmodule WhistleWeb.RegistrationLive do
  alias Whistle.Registrations
  alias Whistle.Seasons
  alias Whistle.Courses
  alias Whistle.Accounts
  alias Whistle.Accounts.Role
  use WhistleWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    subscribe()

    user = socket.assigns.current_user
    season = Seasons.get_current_season()
    is_open = Seasons.is_registration_opened(season)
    courses = if season, do: load_courses(season.id), else: []

    club_members =
      if Role.can_manage_club_users?(user) do
        Accounts.list_manageable_users(user)
      else
        []
      end

    existing_registrations = load_existing_registrations(user, season)
    existing_date_selections = load_existing_date_selections(user, season)

    start_at = if season, do: season.start_registration, else: nil
    is_registration_passed = is_registration_passed?(season)

    {offline_courses_by_date, online_courses} = split_courses(courses)

    {:ok,
     socket
     |> assign(:courses_by_date, offline_courses_by_date)
     |> assign(:online_courses, online_courses)
     |> assign(:online_course_dates, load_online_course_dates(online_courses))
     |> assign(:selected_courses, MapSet.new())
     |> assign(:selected_online_courses, MapSet.new())
     |> assign(:selected_online_dates, %{})
     |> assign(:is_open, is_open)
     |> assign(:season, season)
     |> assign(:start_at, start_at)
     |> assign(:is_registration_passed, is_registration_passed)
     |> assign(:club_members, club_members)
     |> assign(:selected_member_id, nil)
     |> assign(:is_admin, Role.can_manage_club_users?(user))
     |> assign(:existing_registrations, existing_registrations)
     |> assign(:existing_date_selections, existing_date_selections)}
  end

  def handle_info({:course_updated, _course_id}, socket) do
    user = socket.assigns.current_user
    season = socket.assigns.season

    target_user =
      if socket.assigns.selected_member_id do
        Accounts.get_user!(socket.assigns.selected_member_id)
      else
        user
      end

    courses = if season, do: load_courses(season.id), else: []
    existing_registrations = load_existing_registrations(target_user, season)
    existing_date_selections = load_existing_date_selections(target_user, season)
    {offline_courses_by_date, online_courses} = split_courses(courses)

    {:noreply,
     socket
     |> assign(:courses_by_date, offline_courses_by_date)
     |> assign(:online_courses, online_courses)
     |> assign(:online_course_dates, load_online_course_dates(online_courses))
     |> assign(:existing_registrations, existing_registrations)
     |> assign(:existing_date_selections, existing_date_selections)}
  end

  def handle_event("toggle_course", %{"course-id" => course_id_str}, socket) do
    with {:ok, course_id} <- parse_id(course_id_str) do
      selected = socket.assigns.selected_courses

      new_selected =
        if MapSet.member?(selected, course_id) do
          MapSet.delete(selected, course_id)
        else
          MapSet.put(selected, course_id)
        end

      {:noreply, assign(socket, :selected_courses, new_selected)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_online_course", %{"course-id" => course_id_str}, socket) do
    with {:ok, course_id} <- parse_id(course_id_str) do
      selected = socket.assigns.selected_online_courses

      new_selected =
        if MapSet.member?(selected, course_id) do
          MapSet.delete(selected, course_id)
        else
          MapSet.put(selected, course_id)
        end

      {:noreply, assign(socket, :selected_online_courses, new_selected)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "select_online_date",
        %{"course-id" => course_id_str, "kind" => kind, "date-id" => date_id_str},
        socket
      ) do
    with {:ok, course_id} <- parse_id(course_id_str),
         {:ok, date_id} <- parse_id(date_id_str) do
      new_selected =
        socket.assigns.selected_online_dates
        |> Map.update(course_id, %{kind => date_id}, &Map.put(&1, kind, date_id))

      {:noreply, assign(socket, :selected_online_dates, new_selected)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select_member", %{"member_id" => ""}, socket) do
    user = socket.assigns.current_user
    season = socket.assigns.season
    existing_registrations = load_existing_registrations(user, season)
    existing_date_selections = load_existing_date_selections(user, season)

    {:noreply,
     socket
     |> assign(:selected_member_id, nil)
     |> assign(:existing_registrations, existing_registrations)
     |> assign(:existing_date_selections, existing_date_selections)}
  end

  def handle_event("select_member", %{"member_id" => member_id}, socket) do
    with {:ok, member_id} <- parse_id(member_id) do
      member = Accounts.get_user!(member_id)
      season = socket.assigns.season
      existing_registrations = load_existing_registrations(member, season)
      existing_date_selections = load_existing_date_selections(member, season)

      {:noreply,
       socket
       |> assign(:selected_member_id, member_id)
       |> assign(:existing_registrations, existing_registrations)
       |> assign(:existing_date_selections, existing_date_selections)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("enroll", _params, socket) do
    user = socket.assigns.current_user

    target_user =
      if socket.assigns.selected_member_id do
        Accounts.get_user!(socket.assigns.selected_member_id)
      else
        user
      end

    registered_by = if target_user.id != user.id, do: user.id, else: nil

    # Enroll offline courses
    offline_course_ids = MapSet.to_list(socket.assigns.selected_courses)

    offline_results =
      offline_course_ids
      |> Enum.map(&Courses.get_course!/1)
      |> then(&Registrations.enroll(target_user, &1, registered_by))

    # Enroll online courses that have complete date selections
    online_results =
      socket.assigns.selected_online_courses
      |> MapSet.to_list()
      |> Enum.map(fn course_id ->
        course = Courses.get_course!(course_id)
        date_selection = Map.get(socket.assigns.selected_online_dates, course_id, %{})
        mandatory_id = Map.get(date_selection, "mandatory")
        elective_id = Map.get(date_selection, "elective")

        date_ids = if mandatory_id && elective_id, do: [mandatory_id, elective_id], else: nil
        Registrations.enroll_one(target_user, course, registered_by, date_ids)
      end)

    all_results = offline_results ++ online_results

    {successes, errors} =
      Enum.split_with(all_results, fn
        {:ok, _} -> true
        _ -> false
      end)

    enrolled_course_ids =
      offline_course_ids ++ MapSet.to_list(socket.assigns.selected_online_courses)

    socket =
      Enum.reduce(successes, socket, fn {:ok, _reg}, acc ->
        put_flash(acc, :info, "Erfolgreich angemeldet!")
      end)

    socket =
      Enum.reduce(errors, socket, fn {:error, error}, acc ->
        put_flash(acc, :error, format_error(error))
      end)

    Enum.each(enrolled_course_ids, &broadcast({:course_updated, &1}))

    {:noreply,
     socket
     |> assign(:selected_courses, MapSet.new())
     |> assign(:selected_online_courses, MapSet.new())
     |> assign(:selected_online_dates, %{})
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

  defp load_existing_date_selections(user, season) do
    if season do
      Registrations.list_registrations_view(season_id: season.id)
      |> Enum.filter(&(&1.user_id == user.id and &1.course_online))
      |> Map.new(fn reg ->
        {reg.course_id, Courses.list_date_selections_for_registration(reg.registration_id)}
      end)
    else
      %{}
    end
  end

  defp split_courses(courses) do
    {online, offline} = Enum.split_with(courses, & &1.online)

    offline_by_date =
      offline
      |> Enum.group_by(& &1.date)
      |> Enum.reject(fn {date, _} -> is_nil(date) end)
      |> Enum.sort_by(fn {date, _} -> date end, {:asc, Date})

    {offline_by_date, online}
  end

  defp load_online_course_dates(online_courses) do
    online_courses
    |> Enum.map(fn course ->
      full_course = Courses.get_course!(course.id)
      dates = Courses.list_course_dates_with_topics(full_course)
      {course.id, dates}
    end)
    |> Map.new()
  end

  # Compute the set of course types already "spoken for":
  # existing registrations + currently selected offline courses + currently selected online courses.
  defp active_types(
         courses_by_date,
         online_courses,
         selected_courses,
         selected_online_courses,
         existing_registrations
       ) do
    all_courses =
      Enum.flat_map(courses_by_date, fn {_, cs} -> cs end) ++ online_courses

    all_courses
    |> Enum.filter(fn c ->
      MapSet.member?(existing_registrations, c.id) or
        MapSet.member?(selected_courses, c.id) or
        MapSet.member?(selected_online_courses, c.id)
    end)
    |> Enum.map(& &1.type)
    |> MapSet.new()
  end

  defp course_disabled?(
         course,
         selected_courses,
         selected_online_courses,
         courses_by_date,
         online_courses,
         existing_registrations
       ) do
    already_registered = MapSet.member?(existing_registrations, course.id)

    # A selected-but-not-yet-registered course is never disabled (it's the one being toggled)
    if MapSet.member?(selected_courses, course.id) and not already_registered do
      false
    else
      total_count =
        MapSet.size(existing_registrations) +
          MapSet.size(selected_courses) +
          MapSet.size(selected_online_courses)

      cond do
        already_registered ->
          true

        total_count >= 2 ->
          true

        course.type in ["F", "J", "G"] ->
          types =
            active_types(
              courses_by_date,
              online_courses,
              selected_courses,
              selected_online_courses,
              existing_registrations
            )

          MapSet.member?(types, course.type)

        true ->
          false
      end
    end
  end

  defp online_course_disabled?(
         course,
         selected_courses,
         selected_online_courses,
         courses_by_date,
         online_courses,
         existing_registrations
       ) do
    already_registered = MapSet.member?(existing_registrations, course.id)

    if MapSet.member?(selected_online_courses, course.id) and not already_registered do
      false
    else
      total_count =
        MapSet.size(existing_registrations) +
          MapSet.size(selected_courses) +
          MapSet.size(selected_online_courses)

      cond do
        already_registered ->
          true

        total_count >= 2 ->
          true

        course.type in ["F", "J", "G"] ->
          types =
            active_types(
              courses_by_date,
              online_courses,
              selected_courses,
              selected_online_courses,
              existing_registrations
            )

          MapSet.member?(types, course.type)

        true ->
          false
      end
    end
  end

  defp online_selection_complete?(course_id, selected_online_dates) do
    sel = Map.get(selected_online_dates, course_id, %{})
    not is_nil(Map.get(sel, "mandatory")) and not is_nil(Map.get(sel, "elective"))
  end

  defp pending_count(selected_courses, selected_online_courses) do
    MapSet.size(selected_courses) + MapSet.size(selected_online_courses)
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

  defp format_error({:not_available, _}) do
    "Dieser Termin ist ausgebucht."
  end

  defp format_error({:not_allowed, _}) do
    "Anmeldung nicht erlaubt (Limit erreicht oder bereits einen F-Kurs gebucht)."
  end

  defp format_error({:invalid_selection, _}) do
    "Bitte wähle genau einen Pflichttermin und einen Wahlpflichttermin aus."
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

  defp parse_id(id), do: WhistleWeb.ControllerHelpers.parse_id(id)

  def render(assigns) do
    ~H"""
    <div class="space-y-6 pb-24">
      <h2 class="text-2xl font-bold">Kursanmeldung</h2>

      <%= if !@is_open && @is_registration_passed do %>
        <div class="rounded-lg border border-yellow-200 bg-yellow-50 p-4 text-yellow-800">
          Die Kursanmeldung ist beendet. Sie wird im nächsten Jahr wieder freigegeben.
        </div>
      <% end %>

      <%= if !@is_open && !@is_registration_passed && @start_at do %>
        <div class="rounded-lg border border-yellow-200 bg-yellow-50 p-4 text-yellow-800">
          Leider ist die Kursanmeldung noch nicht freigegeben. Sie wird am {Calendar.strftime(
            @start_at,
            "%d.%m.%Y"
          )} geöffnet.
        </div>
      <% end %>

      <%= if !@is_open && !@is_registration_passed && !@start_at do %>
        <div class="rounded-lg border border-yellow-200 bg-yellow-50 p-4 text-yellow-800">
          Leider ist die Kursanmeldung noch nicht freigegeben und ein Termin steht noch nicht fest.
        </div>
      <% end %>

      <%= if @is_open do %>
        <.form for={%{}} phx-submit="enroll" id="enroll-form">
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

          <%= if @courses_by_date == [] && @online_courses == [] do %>
            <div class="text-center py-12 text-zinc-500">
              <.icon name="hero-calendar" class="h-16 w-16 mx-auto mb-4 opacity-50" />
              <p>Keine Kurse verfügbar.</p>
            </div>
          <% end %>

          <%= if @online_courses != [] do %>
            <div class="mb-8">
              <h3 class="font-semibold mb-4">Online-Kurse</h3>
              <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                <%= for course <- @online_courses do %>
                  <% already_registered = MapSet.member?(@existing_registrations, course.id) %>
                  <% disabled =
                    online_course_disabled?(
                      course,
                      @selected_courses,
                      @selected_online_courses,
                      @courses_by_date,
                      @online_courses,
                      @existing_registrations
                    ) %>
                  <% selected = MapSet.member?(@selected_online_courses, course.id) %>
                  <% dates = Map.get(@online_course_dates, course.id, []) %>
                  <% mandatory_dates = Enum.filter(dates, &(&1.kind == :mandatory)) %>
                  <% elective_dates = Enum.filter(dates, &(&1.kind == :elective)) %>
                  <% date_selection = Map.get(@selected_online_dates, course.id, %{}) %>
                  <% topics = elective_dates |> Enum.group_by(& &1.course_date_topic_id) %>
                  <% complete = online_selection_complete?(course.id, @selected_online_dates) %>
                  <% registered_selections = Map.get(@existing_date_selections, course.id, []) %>

                  <div class={[
                    "rounded-lg border p-4 shadow-sm transition-all",
                    if(disabled,
                      do: "bg-zinc-100 border-zinc-200 opacity-50",
                      else: "bg-white border-zinc-200 hover:shadow-md"
                    ),
                    if(selected and not disabled, do: "ring-2 ring-blue-500", else: "")
                  ]}>
                    <div
                      class={if disabled, do: "cursor-not-allowed", else: "cursor-pointer"}
                      phx-click={unless disabled or already_registered, do: "toggle_online_course"}
                      phx-value-course-id={course.id}
                    >
                      <div class="flex gap-3">
                        <div class="flex-1">
                          <h4 class="font-bold text-base mb-3">{course.name}</h4>
                          <div class="text-sm text-zinc-600 space-y-1">
                            <div class="flex items-center gap-2">
                              <.icon name="hero-users" class="h-4 w-4" />
                              {course.participants} / {course.max_participants}
                            </div>
                          </div>
                        </div>
                        <div class="flex flex-col items-end gap-2">
                          <%= if already_registered do %>
                            <span class="text-xs text-green-700 font-medium bg-green-50 border border-green-200 rounded-full px-2 py-0.5">
                              Angemeldet
                            </span>
                          <% else %>
                            <input
                              type="checkbox"
                              checked={selected}
                              disabled={disabled}
                              class="h-4 w-4 rounded border-gray-300 flex-shrink-0 pointer-events-none"
                              readonly
                            />
                          <% end %>
                          <div class="flex items-center gap-1">
                            <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border " <> type_badge_color(course.type)}>
                              {course.type}
                            </span>
                            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border bg-orange-100 text-orange-800 border-orange-300">
                              Online
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>

                    <%= if already_registered and registered_selections != [] do %>
                      <div class="mt-4 pt-4 border-t border-zinc-100 space-y-2">
                        <%= for %{date: date, topic: topic} <- registered_selections do %>
                          <div class="flex items-start gap-2 text-sm text-zinc-600">
                            <.icon
                              name={
                                if date.kind == :mandatory, do: "hero-calendar", else: "hero-bookmark"
                              }
                              class="h-4 w-4 mt-0.5 flex-shrink-0"
                            />
                            <div>
                              <span>
                                {Calendar.strftime(date.date, "%d.%m.%Y")} · {Time.to_string(
                                  date.time
                                )
                                |> String.slice(0, 5)} Uhr
                              </span>
                              <%= if topic do %>
                                <span class="ml-1 text-zinc-400">({topic.name})</span>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                    <%= if selected and not disabled and (mandatory_dates != [] or elective_dates != []) do %>
                      <div class="mt-4 pt-4 border-t border-zinc-100 space-y-4">
                        <%= if mandatory_dates != [] do %>
                          <div>
                            <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500 mb-2">
                              Pflichttermin
                            </p>
                            <div class="space-y-1">
                              <%= for date <- mandatory_dates do %>
                                <label class="flex items-center gap-2 cursor-pointer">
                                  <input
                                    type="radio"
                                    name={"mandatory_#{course.id}"}
                                    phx-click="select_online_date"
                                    phx-value-course-id={course.id}
                                    phx-value-kind="mandatory"
                                    phx-value-date-id={date.id}
                                    checked={Map.get(date_selection, "mandatory") == date.id}
                                    class="h-4 w-4"
                                  />
                                  <span class="text-sm">
                                    {Calendar.strftime(date.date, "%d.%m.%Y")} · {Time.to_string(
                                      date.time
                                    )
                                    |> String.slice(0, 5)} Uhr
                                  </span>
                                </label>
                              <% end %>
                            </div>
                          </div>
                        <% end %>

                        <%= if elective_dates != [] do %>
                          <div>
                            <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500 mb-2">
                              Wahlpflichttermin
                            </p>
                            <%= for {_topic_id, topic_dates} <- topics do %>
                              <% topic = hd(topic_dates).topic %>
                              <div class="mb-2">
                                <%= if topic do %>
                                  <p class="text-xs text-zinc-400 mb-1">{topic.name}</p>
                                <% end %>
                                <div class="space-y-1">
                                  <%= for date <- topic_dates do %>
                                    <label class="flex items-center gap-2 cursor-pointer">
                                      <input
                                        type="radio"
                                        name={"elective_#{course.id}"}
                                        phx-click="select_online_date"
                                        phx-value-course-id={course.id}
                                        phx-value-kind="elective"
                                        phx-value-date-id={date.id}
                                        checked={Map.get(date_selection, "elective") == date.id}
                                        class="h-4 w-4"
                                      />
                                      <span class="text-sm">
                                        {Calendar.strftime(date.date, "%d.%m.%Y")} · {Time.to_string(
                                          date.time
                                        )
                                        |> String.slice(0, 5)} Uhr
                                      </span>
                                    </label>
                                  <% end %>
                                </div>
                              </div>
                            <% end %>
                          </div>
                        <% end %>

                        <%= if not complete do %>
                          <p class="text-xs text-amber-600">
                            Bitte wähle einen Pflicht- und einen Wahlpflichttermin.
                          </p>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

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
                      @selected_online_courses,
                      @courses_by_date,
                      @online_courses,
                      @existing_registrations
                    ) %>
                  <% selected = MapSet.member?(@selected_courses, course.id) or already_registered %>

                  <div
                    class={[
                      "rounded-lg border border-zinc-200 p-4 shadow-sm cursor-pointer transition-all relative",
                      if(disabled,
                        do: "bg-zinc-100 opacity-50 cursor-not-allowed",
                        else: "bg-white hover:shadow-md"
                      ),
                      if(selected, do: "ring-2 ring-blue-500", else: "")
                    ]}
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
        </.form>

        <% total = pending_count(@selected_courses, @selected_online_courses) %>
        <div class={[
          "fixed bottom-0 left-0 right-0 md:left-64 z-30 border-t border-base-300 bg-base-100/95 backdrop-blur px-4 py-3 sm:px-6 lg:px-10 transition-all duration-200",
          if(total > 0, do: "translate-y-0", else: "translate-y-full")
        ]}>
          <div class="mx-auto flex w-full max-w-6xl items-center justify-between gap-4">
            <p class="text-sm text-base-content/70">
              {total} {if total == 1, do: "Kurs", else: "Kurse"} ausgewählt
            </p>
            <.button type="submit" form="enroll-form">
              Anmelden
            </.button>
          </div>
        </div>
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
