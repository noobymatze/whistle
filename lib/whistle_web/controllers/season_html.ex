defmodule WhistleWeb.SeasonHTML do
  use WhistleWeb, :html

  embed_templates "season_html/*"

  @doc """
  Renders a season form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :season, :map, default: nil

  def season_form(assigns)

  @doc """
  Returns a hint for usage of the form.
  """
  def form_hint(assigns) do
    ~H"""
    Verwende dieses Formular, um Saisons zu verwalten/eine neue Saison anzulegen.
    <p class="mt-2 text-sm text-zinc-600">
      Das Start-Datum einer Saison legt gleichzeitig auch das Ende der vorherigen
      Saison fest. Mittels Start- und Endzeitpunkt für die Registrierung kann der
      Zeitpunkt der Kursanmeldung festgelegt werden.
    </p>
    """
  end
end
