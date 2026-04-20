defmodule WhistleWeb.SeasonHTML do
  use WhistleWeb, :html

  embed_templates "season_html/*"

  @doc """
  Renders a season form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :season, :map, default: nil
  attr :current_user, :map, required: true

  def season_form(assigns)
end
