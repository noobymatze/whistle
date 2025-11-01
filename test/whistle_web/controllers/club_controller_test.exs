defmodule WhistleWeb.ClubControllerTest do
  use WhistleWeb.ConnCase

  import Whistle.ClubsFixtures
  import Whistle.AssociationsFixtures

  setup :register_and_log_in_user

  @create_attrs %{name: "some name", short_name: "some short_name"}
  @update_attrs %{name: "some updated name", short_name: "some updated short_name"}
  @invalid_attrs %{name: nil, short_name: nil}

  describe "index" do
    test "lists all clubs", %{conn: conn} do
      conn = get(conn, ~p"/admin/clubs")
      assert html_response(conn, 200) =~ "Vereine"
    end
  end

  describe "new club" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/admin/clubs/new")
      assert html_response(conn, 200) =~ "Neuer Verein"
    end
  end

  describe "create club" do
    test "redirects to show when data is valid", %{conn: conn} do
      association = association_fixture()

      conn =
        post(conn, ~p"/admin/clubs",
          club: Map.put(@create_attrs, :association_id, association.id)
        )

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/admin/clubs/#{id}/edit"

      conn = get(conn, ~p"/admin/clubs/#{id}/edit")
      assert html_response(conn, 200) =~ "Verein bearbeiten"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/admin/clubs", club: @invalid_attrs)
      assert html_response(conn, 200) =~ "Neuer Verein"
    end
  end

  describe "edit club" do
    setup [:create_club]

    test "renders form for editing chosen club", %{conn: conn, club: club} do
      conn = get(conn, ~p"/admin/clubs/#{club}/edit")
      assert html_response(conn, 200) =~ "Verein bearbeiten"
    end
  end

  describe "update club" do
    setup [:create_club]

    test "redirects when data is valid", %{conn: conn, club: club} do
      conn = put(conn, ~p"/admin/clubs/#{club}", club: @update_attrs)
      assert redirected_to(conn) == ~p"/admin/clubs/#{club}/edit"

      conn = get(conn, ~p"/admin/clubs/#{club}/edit")
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "renders errors when data is invalid", %{conn: conn, club: club} do
      conn = put(conn, ~p"/admin/clubs/#{club}", club: @invalid_attrs)
      assert html_response(conn, 200) =~ "Verein bearbeiten"
    end
  end

  describe "delete club" do
    setup [:create_club]

    test "deletes chosen club", %{conn: conn, club: club} do
      conn = delete(conn, ~p"/admin/clubs/#{club}")
      assert redirected_to(conn) == ~p"/admin/clubs"

      assert_error_sent 404, fn ->
        get(conn, ~p"/admin/clubs/#{club}/edit")
      end
    end
  end

  defp create_club(_) do
    club = club_fixture()
    %{club: club}
  end
end
