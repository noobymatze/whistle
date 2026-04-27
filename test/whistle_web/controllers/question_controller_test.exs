defmodule WhistleWeb.QuestionControllerTest do
  use WhistleWeb.ConnCase, async: true

  import Whistle.AccountsFixtures
  import Whistle.ExamsFixtures

  alias Whistle.Accounts
  alias Whistle.Exams

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

  test "creating a question can assign it to an exam variant", %{conn: conn} do
    variant = exam_variant_fixture(%{name: "Direktzuordnung"})

    conn =
      post(conn, ~p"/admin/questions", %{
        "question" => %{
          "type" => "single_choice",
          "difficulty" => "low",
          "body_markdown" => "Neue Frage fuer Variante?",
          "status" => "active"
        },
        "choices" => %{
          "0" => %{"body_markdown" => "Ja", "is_correct" => "true"},
          "1" => %{"body_markdown" => "Nein"}
        },
        "course_types" => ["F"],
        "exam_variants" => [to_string(variant.id)]
      })

    assert redirected_to(conn) =~ "/admin/questions/"

    [assignment] = Exams.list_exam_variant_questions(variant)
    assert assignment.question.body_markdown == "Neue Frage fuer Variante?"
    assert assignment.position == 1
  end
end
