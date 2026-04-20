defmodule WhistleWeb.MyCoursesLive do
  use WhistleWeb, :live_view
  import Ecto.Query
  alias Whistle.Repo
  alias Whistle.Courses
  alias Whistle.Registrations.RegistrationView

  on_mount WhistleWeb.UserAuthLive

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    {registrations, date_selections} = load_registrations(user.id)

    {:ok, assign(socket, registrations: registrations, date_selections: date_selections)}
  end

  def handle_event("unenroll", %{"course_id" => course_id}, socket) do
    user = socket.assigns.current_user

    query =
      from r in "registrations",
        where: r.user_id == ^user.id and r.course_id == ^course_id and is_nil(r.unenrolled_at),
        update: [
          set: [
            unenrolled_at: fragment("NOW()"),
            unenrolled_by: ^user.id
          ]
        ]

    case Repo.update_all(query, []) do
      {1, _} ->
        {registrations, date_selections} = load_registrations(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Erfolgreich abgemeldet")
         |> assign(registrations: registrations, date_selections: date_selections)}

      _ ->
        {:noreply, put_flash(socket, :error, "Fehler beim Abmelden")}
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

  defp load_registrations(user_id) do
    regs =
      from(r in RegistrationView,
        where: r.user_id == ^user_id,
        order_by: [desc: r.year, desc: r.course_date]
      )
      |> Repo.all()

    date_selections =
      regs
      |> Enum.filter(& &1.course_online)
      |> Map.new(fn r ->
        {r.registration_id, Courses.list_date_selections_for_registration(r.registration_id)}
      end)

    {Enum.group_by(regs, & &1.year), date_selections}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= for {year, registrations} <- @registrations |> Enum.sort_by(fn {year, _} -> year end, :desc) do %>
        <div>
          <h3 class="text-2xl font-semibold mb-4">Saison {year}</h3>
          <div class="grid gap-4 md:grid-cols-2">
            <%= for registration <- registrations do %>
              <% selections = Map.get(@date_selections, registration.registration_id, []) %>
              <div class={"rounded-lg border border-zinc-200 p-4 shadow-sm " <> if registration.unenrolled_at, do: "bg-zinc-100 opacity-60", else: "bg-white"}>
                <div class="flex gap-3">
                  <div class="flex-1">
                    <h4 class="font-bold text-base mb-3">{registration.course_name}</h4>
                    <div class="text-sm text-zinc-600 space-y-1">
                      <%= if registration.course_online do %>
                        <div class="flex items-center gap-2">
                          <.icon name="hero-users" class="h-4 w-4" /> Online
                        </div>
                      <% else %>
                        <%= if registration.course_date do %>
                          <div class="flex items-center gap-2">
                            <.icon name="hero-calendar" class="h-4 w-4" />
                            {Calendar.strftime(registration.course_date, "%d.%m.%Y")}
                          </div>
                        <% end %>
                        <%= if registration.organizer_name do %>
                          <div class="flex items-center gap-2">
                            <.icon name="hero-map-pin" class="h-4 w-4" />
                            {registration.organizer_name}
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex flex-col items-end gap-2">
                    <%= if is_nil(registration.unenrolled_at) do %>
                      <span class="text-xs text-green-700 font-medium bg-green-50 border border-green-200 rounded-full px-2 py-0.5">
                        Angemeldet
                      </span>
                    <% end %>
                    <div class="flex items-center gap-1">
                      <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border " <> type_badge_color(registration.course_type)}>
                        {registration.course_type}
                      </span>
                      <%= if registration.course_online do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border bg-orange-100 text-orange-800 border-orange-300">
                          Online
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>

                <%= if registration.course_online and is_nil(registration.unenrolled_at) and selections != [] do %>
                  <div class="mt-4 pt-4 border-t border-zinc-100 space-y-2">
                    <%= for %{date: date, topic: topic} <- selections do %>
                      <div class="flex items-start gap-2 text-sm text-zinc-600">
                        <.icon
                          name={
                            if date.kind == :mandatory, do: "hero-calendar", else: "hero-bookmark"
                          }
                          class="h-4 w-4 mt-0.5 flex-shrink-0"
                        />
                        <div>
                          <span>
                            {Calendar.strftime(date.date, "%d.%m.%Y")} · {Time.to_string(date.time)
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

                <div class="mt-4 flex justify-end">
                  <%= if registration.unenrolled_at do %>
                    <div class="text-sm text-zinc-500">
                      Abgemeldet am {Whistle.Timezone.format_local(
                        registration.unenrolled_at,
                        "%d.%m.%Y"
                      )}
                    </div>
                  <% else %>
                    <.link
                      phx-click="unenroll"
                      phx-value-course_id={registration.course_id}
                      data-confirm="Möchten Sie sich wirklich von diesem Kurs abmelden?"
                      class="underline font-bold text-sm"
                    >
                      Abmelden
                    </.link>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @registrations == %{} do %>
        <div class="text-center py-12 text-zinc-500">
          <.icon name="hero-academic-cap" class="h-16 w-16 mx-auto mb-4 opacity-50" />
          <p>Sie haben sich noch für keine Kurse angemeldet.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
