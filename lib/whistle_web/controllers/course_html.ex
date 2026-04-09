defmodule WhistleWeb.CourseHTML do
  use WhistleWeb, :html

  embed_templates "course_html/*"

  @doc """
  Renders a course form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :clubs, :list, required: true
  attr :types, :list, required: true
  attr :seasons, :list, required: true
  attr :action, :string, required: true
  attr :course, :map, default: nil
  attr :current_user, :map, required: true

  def course_form(assigns)
end
