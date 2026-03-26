defmodule WhistleWeb.ErrorHTMLTest do
  use WhistleWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(WhistleWeb.ErrorHTML, "404", "html", [])

    assert html =~ "Seite nicht gefunden"
    assert html =~ "Zur Startseite"
  end

  test "renders 500.html" do
    assert render_to_string(WhistleWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
