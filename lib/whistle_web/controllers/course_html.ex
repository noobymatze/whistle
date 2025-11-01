defmodule WhistleWeb.CourseHTML do
  use WhistleWeb, :html

  embed_templates "course_html/*"

  @doc """
  Renders a course form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :clubs, :list, required: true
  attr :types, :list, required: true
  attr :action, :string, required: true
  attr :course, :map, default: nil

  def course_form(assigns)

  @doc """
  Returns a hint for usage of the form.
  """
  def form_hint(assigns) do
    ~H"""
    Verwende dieses Formular, um Kurse zu verwalten und anzulegen.
    """
  end
end
