defmodule WhistleWeb.QuestionControllerTest do
  use WhistleWeb.ConnCase, async: true

  import Whistle.AccountsFixtures

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
end
