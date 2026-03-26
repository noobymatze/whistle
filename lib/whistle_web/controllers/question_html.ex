defmodule WhistleWeb.QuestionHTML do
  use WhistleWeb, :html

  embed_templates "question_html/*"

  @doc """
  Renders Markdown as safe HTML using Earmark.
  """
  def render_markdown(nil), do: ""
  def render_markdown(""), do: ""

  def render_markdown(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown, escape: false) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      {:error, _, _} -> Phoenix.HTML.raw(Phoenix.HTML.html_escape(markdown))
    end
  end

  def form_hint(assigns) do
    ~H"""
    Pflichtfelder sind mit * markiert.
    """
  end
end
