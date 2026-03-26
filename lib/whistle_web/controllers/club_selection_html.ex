defmodule WhistleWeb.ClubSelectionHTML do
  use WhistleWeb, :html

  def index(assigns) do
    ~H"""
    <h2 class="text-2xl font-bold">Bei welchem Verein bist du?</h2>
    <p class="mt-2 text-zinc-700 ">
      Herzlich Willkommen! Du hast dich erfolgreich angemeldet,
      bist aber leider noch keinem Verein zugewiesen. Bitte wähle
      in der folgenden Liste deinen Verein aus und <b>klicke</b> auf ihn.
    </p>
    <ul class="mt-6">
      <%= for club <- @clubs do %>
        <li class="mt-2">
          <.link class="hover:underline" href={~p"/users/settings/clubs/select/#{club.id}"}>
            {club.name}
            <.icon name="hero-arrow-right-solid" class="h-3 w-3" />
          </.link>
        </li>
      <% end %>
    </ul>
    """
  end
end
