defmodule WhistleWeb.ExamVariantHTML do
  use WhistleWeb, :html

  embed_templates "exam_variant_html/*"

  def status_label("draft"), do: "Entwurf"
  def status_label("enabled"), do: "Aktiviert"
  def status_label("disabled"), do: "Deaktiviert"
  def status_label(status), do: status

  def difficulty_label("low"), do: "Einfach"
  def difficulty_label("medium"), do: "Mittel"
  def difficulty_label("high"), do: "Schwer"
  def difficulty_label(difficulty), do: difficulty

  def type_label("single_choice"), do: "Eine Antwort"
  def type_label("multiple_choice"), do: "Multiple-Choice"
  def type_label("text"), do: "Text"
  def type_label(type), do: type
end
