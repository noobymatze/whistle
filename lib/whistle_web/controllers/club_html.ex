defmodule WhistleWeb.ClubHTML do
  use WhistleWeb, :html

  embed_templates "club_html/*"

  @doc """
  Renders a club form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :associations, :list, required: true
  attr :action, :string, required: true
  attr :club, :map, default: nil

  def club_form(assigns)
end
