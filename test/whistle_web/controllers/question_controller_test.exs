defmodule WhistleWeb.QuestionControllerTest do
  use WhistleWeb.ConnCase, async: true

  import Whistle.AccountsFixtures
  import Whistle.ExamsFixtures

  alias Whistle.Accounts

  setup %{conn: conn} do
    admin = user_fixture(%{role: "ADMIN"})
    token = Accounts.generate_user_session_token(admin)

    conn =
      conn
      |> init_test_session(%{})
      |> put_session(:user_token, token)

    {:ok, conn: conn}
  end

  test "renders 404 for missing numeric ids", %{conn: conn} do
    conn = get(conn, ~p"/admin/questions/999999/edit")

    assert html_response(conn, 404) =~ "Seite nicht gefunden"
  end

  test "renders 404 for malformed ids", %{conn: conn} do
    conn = get(conn, ~p"/admin/questions/abc/edit")

    assert html_response(conn, 404) =~ "Seite nicht gefunden"
  end

  test "index shows test variants", %{conn: conn} do
    variant = exam_variant_fixture(%{name: "Fragenbereich F1"})

    conn = get(conn, ~p"/admin/questions")
    html = html_response(conn, 200)

    assert html =~ ~s(id="exam-variants-on-questions")
    assert html =~ ~s(id="question-page-exam-variant-#{variant.id}")
    assert html =~ "Fragenbereich F1"
  end
end
