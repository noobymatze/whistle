defmodule WhistleWeb.RegistrationControllerTest do
  use WhistleWeb.ConnCase

  import Whistle.RegistrationsFixtures

  setup :register_and_log_in_user

  describe "index" do
    test "lists all registrations", %{conn: conn} do
      conn = get(conn, ~p"/admin/registrations")
      assert html_response(conn, 200) =~ "Kursanmeldungen"
    end
  end

  describe "delete registration" do
    setup [:create_registration]

    test "deletes chosen registration", %{conn: conn, registration: registration} do
      conn =
        delete(conn, ~p"/admin/registrations/#{registration.course_id}/#{registration.user_id}")

      assert redirected_to(conn) == ~p"/admin/registrations"
    end
  end

  defp create_registration(_) do
    registration = registration_fixture()
    %{registration: registration}
  end
end
