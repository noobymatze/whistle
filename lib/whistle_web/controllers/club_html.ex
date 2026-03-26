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

  @doc """
  Returns a hint for usage of the form.
  """
  def form_hint(assigns) do
    ~H"""
    Verwende dieses Formular, um Vereine zu verwalten und neue Vereine anzulegen.
    """
  end
end
