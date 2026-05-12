defmodule Whistle.AccountsFixtures do
  alias Whistle.Accounts.UserInvitation
  alias Whistle.ClubsFixtures
  alias Whistle.Repo

  @moduledoc """
  This module defines test helpers for creating
  entities via the `Whistle.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def unique_username, do: "u#{System.unique_integer() |> abs() |> rem(1_000_000_000)}"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      username: unique_username(),
      password: valid_user_password(),
      first_name: "Test",
      last_name: "User",
      birthday: ~D[1990-01-01]
    })
  end

  def user_fixture(attrs \\ %{}) do
    club_id =
      if Map.has_key?(attrs, :club_id) or Map.has_key?(attrs, "club_id") do
        Map.get(attrs, :club_id, Map.get(attrs, "club_id"))
      else
        ClubsFixtures.club_fixture().id
      end

    # Extract role before passing attrs to register_user (registration_changeset
    # intentionally does not accept :role or :club_id to prevent privilege escalation).
    role = Map.get(attrs, :role) || Map.get(attrs, "role")
    attrs_without_role = Map.drop(attrs, [:role, "role", :club_id, "club_id"])

    {:ok, user} =
      attrs_without_role
      |> valid_user_attributes()
      |> Whistle.Accounts.register_user()

    user =
      if club_id do
        {:ok, updated} = Whistle.Accounts.update_club(user, %{id: club_id})
        updated
      else
        user
      end

    # Apply role if explicitly requested (test-only path via update_user_role)
    user =
      if role && role != Whistle.Accounts.Role.default_role() do
        super_admin = %{role: "SUPER_ADMIN"}
        {:ok, updated} = Whistle.Accounts.update_user_role(user, role, super_admin)
        updated
      else
        user
      end

    user
  end

  def invitation_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    inviter = Map.get(attrs, :invited_by_user) || user_fixture(%{role: "ADMIN"})
    {code, code_hash} = UserInvitation.generate_code()

    attrs =
      attrs
      |> Map.drop([:invited_by_user])
      |> Enum.into(%{
        email: unique_user_email(),
        code_hash: code_hash,
        invited_by_user_id: inviter.id,
        club_id: inviter.club_id,
        expires_at: UserInvitation.expires_at()
      })

    {:ok, invitation} =
      %UserInvitation{}
      |> UserInvitation.create_changeset(attrs)
      |> Repo.insert()

    {invitation, code}
  end

  def extract_user_token(fun) do
    {:ok, _job} = fun.(&"[TOKEN]#{&1}[TOKEN]")

    captured_email =
      receive do
        {:email, email} -> email
      after
        1_000 -> raise "expected an email to be delivered"
      end

    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
