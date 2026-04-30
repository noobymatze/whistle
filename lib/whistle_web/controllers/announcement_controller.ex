defmodule WhistleWeb.AnnouncementController do
  use WhistleWeb, :controller

  alias Whistle.Accounts

  @slug "2026-04-30-new-system"
  @subject "Neues System für die Schiedsrichterkurse"
  @body """
  Hey,

  für die Anmeldung zu den Schiedsrichterkursen nutzen wir ein neues System.
  Dein Benutzername lautet: {username}

  Verwende die Passwort-Vergessen Funktion, um dir ein neues Passwort zu
  erstellen und dich damit anzumelden. Die Kursanmeldung wird am 10.05.
  freigeschaltet.

  Viele Grüße

  Die RSK
  """

  plug :require_admin_username

  def index(conn, _params) do
    render(conn, :index,
      subject: @subject,
      body: @body,
      recipient_count: Accounts.count_announcement_recipients()
    )
  end

  def create(conn, _params) do
    {:ok, jobs} = Accounts.broadcast_announcement(@slug, @subject, @body)

    conn
    |> put_flash(:info, "#{length(jobs)} E-Mails in die Queue gestellt.")
    |> redirect(to: ~p"/admin/announcement")
  end

  defp require_admin_username(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && user.username == "admin" do
      conn
    else
      conn
      |> put_flash(:error, "Nicht erlaubt.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end
