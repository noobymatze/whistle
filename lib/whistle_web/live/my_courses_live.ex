defmodule WhistleWeb.MyCoursesLive do
  use WhistleWeb, :live_view
  import Ecto.Query
  alias Whistle.Repo
  alias Whistle.Registrations.RegistrationView

  on_mount WhistleWeb.UserAuthLive

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    registrations = load_registrations(user.id)

    {:ok, assign(socket, registrations: registrations)}
  end

  def handle_event("unenroll", %{"course_id" => course_id}, socket) do
    user = socket.assigns.current_user

    # Update the registration to mark as unenrolled
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
        registrations = load_registrations(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Erfolgreich abgemeldet")
         |> assign(registrations: registrations)}

      _ ->
        {:noreply, put_flash(socket, :error, "Fehler beim Abmelden")}
    end
  end

  defp load_registrations(user_id) do
    query =
      from r in RegistrationView,
        where: r.user_id == ^user_id,
        order_by: [desc: r.year, desc: r.course_date]

    Repo.all(query)
    |> Enum.group_by(& &1.year)
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= for {year, registrations} <- @registrations |> Enum.sort_by(fn {year, _} -> year end, :desc) do %>
        <div>
          <h3 class="text-2xl font-semibold mb-4">Saison {year}</h3>
          <div class="grid gap-4 md:grid-cols-2">
            <%= for registration <- registrations do %>
              <div class={"rounded-lg border p-4 shadow-sm " <> if registration.unenrolled_at, do: "bg-zinc-100 opacity-60", else: "bg-white"}>
                <h4 class="text-lg font-bold mb-2">{registration.course_name}</h4>
                <div class="text-sm text-zinc-600 mb-4">
                  <div class="flex items-center gap-2 mb-1">
                    <.icon name="hero-calendar" class="h-4 w-4" />
                    <%= if registration.course_date do %>
                      {Calendar.strftime(registration.course_date, "%d.%m.%Y")}
                    <% else %>
                      Termin noch nicht bekannt
                    <% end %>
                  </div>
                  <div class="flex items-center gap-2">
                    <.icon name="hero-map-pin" class="h-4 w-4" />
                    {registration.organizer_name}
                  </div>
                </div>

                <div class="flex justify-end">
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
