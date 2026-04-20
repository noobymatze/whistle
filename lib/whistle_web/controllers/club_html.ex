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
  attr :current_user, :map, required: true

  def club_form(assigns)
end
