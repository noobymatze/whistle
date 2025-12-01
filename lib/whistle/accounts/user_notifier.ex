defmodule Whistle.Accounts.UserNotifier do
  import Swoosh.Email

  alias Whistle.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    {from_email, from_name} = get_from_address()

    email =
      new()
      |> to(recipient)
      |> from({from_name, from_email})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # Get the configured from address from application config
  defp get_from_address do
    config = Application.get_env(:whistle, :mailer_from, [])
    email = Keyword.get(config, :email, "noreply@whistle.local")
    name = Keyword.get(config, :name, "Whistle")
    {email, name}
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "E-Mail Bestätigung", """

    ==============================

    Hallo #{user.username},

    Du kannst dein Konto bestätigen, indem du die folgende URL besuchst:

    #{url}

    Falls du kein Konto bei uns erstellt hast, ignoriere diese E-Mail.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Passwort-Zurücksetzen Anweisungen", """

    ==============================

    Hallo #{user.username},

    Du kannst dein Passwort zurücksetzen, indem du die folgende URL besuchst:

    #{url}

    Falls du diese Änderung nicht angefordert hast, ignoriere diese E-Mail.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "E-Mail-Änderungsanweisungen", """

    ==============================

    Hallo #{user.username},

    Du kannst deine E-Mail ändern, indem du die folgende URL besuchst:

    #{url}

    Falls du diese Änderung nicht angefordert hast, ignoriere diese E-Mail.

    ==============================
    """)
  end
end
