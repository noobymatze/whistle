defmodule WhistleWeb.QuestionHTML do
  use WhistleWeb, :html

  embed_templates "question_html/*"

  @doc """
  Renders Markdown as safe HTML using Earmark.
  """
  def render_markdown(nil), do: ""
  def render_markdown(""), do: ""

  def render_markdown(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown, escape: true) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      {:error, _, _} -> Phoenix.HTML.raw(Phoenix.HTML.html_escape(markdown))
    end
  end

  def variant_status_label("draft"), do: "Entwurf"
  def variant_status_label("enabled"), do: "Aktiviert"
  def variant_status_label("disabled"), do: "Deaktiviert"
  def variant_status_label(status), do: status

  def variant_status_class("enabled"), do: "bg-green-100 text-green-700"
  def variant_status_class("disabled"), do: "bg-gray-100 text-gray-500"
  def variant_status_class(_status), do: "bg-yellow-100 text-yellow-700"
end
