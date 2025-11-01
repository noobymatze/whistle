defmodule WhistleWeb.AssociationControllerTest do
  use WhistleWeb.ConnCase

  import Whistle.AssociationsFixtures

  setup :register_and_log_in_user

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  describe "index" do
    test "lists all associations", %{conn: conn} do
      conn = get(conn, ~p"/admin/associations")
      assert html_response(conn, 200) =~ "Verbände"
    end
  end

  describe "new association" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/admin/associations/new")
      assert html_response(conn, 200) =~ "Neuer Verband"
    end
  end

  describe "create association" do
    test "redirects to show when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/admin/associations", association: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/admin/associations/#{id}/edit"

      conn = get(conn, ~p"/admin/associations/#{id}/edit")
      assert html_response(conn, 200) =~ "Verband bearbeiten"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/admin/associations", association: @invalid_attrs)
      assert html_response(conn, 200) =~ "Neuer Verband"
    end
  end

  describe "edit association" do
    setup [:create_association]

    test "renders form for editing chosen association", %{conn: conn, association: association} do
      conn = get(conn, ~p"/admin/associations/#{association}/edit")
      assert html_response(conn, 200) =~ "Verband bearbeiten"
    end
  end

  describe "update association" do
    setup [:create_association]

    test "redirects when data is valid", %{conn: conn, association: association} do
      conn = put(conn, ~p"/admin/associations/#{association}", association: @update_attrs)
      assert redirected_to(conn) == ~p"/admin/associations/#{association}/edit"

      conn = get(conn, ~p"/admin/associations/#{association}/edit")
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "renders errors when data is invalid", %{conn: conn, association: association} do
      conn = put(conn, ~p"/admin/associations/#{association}", association: @invalid_attrs)
      assert html_response(conn, 200) =~ "Verband bearbeiten"
    end
  end

  describe "delete association" do
    setup [:create_association]

    test "deletes chosen association", %{conn: conn, association: association} do
      conn = delete(conn, ~p"/admin/associations/#{association}")
      assert redirected_to(conn) == ~p"/admin/associations"

      assert_error_sent 404, fn ->
        get(conn, ~p"/admin/associations/#{association}/edit")
      end
    end
  end

  defp create_association(_) do
    association = association_fixture()
    %{association: association}
  end
end
