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
end
