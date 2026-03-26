defmodule WhistleWeb.AssociationHTML do
  use WhistleWeb, :html

  embed_templates "association_html/*"

  @doc """
  Renders a association form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :association, :map, default: nil

  def association_form(assigns)
end
