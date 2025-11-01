defmodule WhistleWeb.SeasonControllerTest do
  use WhistleWeb.ConnCase

  import Whistle.SeasonsFixtures

  setup :register_and_log_in_user

  @create_attrs %{
    start: ~D[2024-02-08],
    year: 42,
    start_registration: ~N[2024-02-08 14:30:00],
    end_registration: ~N[2024-02-08 14:30:00]
  }
  @update_attrs %{
    start: ~D[2024-02-09],
    year: 43,
    start_registration: ~N[2024-02-09 14:30:00],
    end_registration: ~N[2024-02-09 14:30:00]
  }
  @invalid_attrs %{start: nil, year: nil, start_registration: nil, end_registration: nil}

  describe "index" do
    test "lists all seasons", %{conn: conn} do
      conn = get(conn, ~p"/admin/seasons")
      assert html_response(conn, 200) =~ "Saisons"
    end
  end

  describe "new season" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/admin/seasons/new")
      assert html_response(conn, 200) =~ "Neue Saison"
    end
  end

  describe "create season" do
    test "redirects to show when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/admin/seasons", season: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/admin/seasons/#{id}/edit"

      conn = get(conn, ~p"/admin/seasons/#{id}/edit")
      assert html_response(conn, 200) =~ "Saison bearbeiten"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/admin/seasons", season: @invalid_attrs)
      assert html_response(conn, 200) =~ "Neue Saison"
    end
  end

  describe "edit season" do
    setup [:create_season]

    test "renders form for editing chosen season", %{conn: conn, season: season} do
      conn = get(conn, ~p"/admin/seasons/#{season}/edit")
      assert html_response(conn, 200) =~ "Saison bearbeiten"
    end
  end

  describe "update season" do
    setup [:create_season]

    test "redirects when data is valid", %{conn: conn, season: season} do
      conn = put(conn, ~p"/admin/seasons/#{season}", season: @update_attrs)
      assert redirected_to(conn) == ~p"/admin/seasons/#{season}/edit"

      conn = get(conn, ~p"/admin/seasons/#{season}/edit")
      assert html_response(conn, 200)
    end

    test "renders errors when data is invalid", %{conn: conn, season: season} do
      conn = put(conn, ~p"/admin/seasons/#{season}", season: @invalid_attrs)
      assert html_response(conn, 200) =~ "Saison bearbeiten"
    end
  end

  describe "delete season" do
    setup [:create_season]

    test "deletes chosen season", %{conn: conn, season: season} do
      conn = delete(conn, ~p"/admin/seasons/#{season}")
      assert redirected_to(conn) == ~p"/admin/seasons"

      assert_error_sent 404, fn ->
        get(conn, ~p"/admin/seasons/#{season}/edit")
      end
    end
  end

  defp create_season(_) do
    season = season_fixture()
    %{season: season}
  end
end
