defmodule Whistle.AccountsFixtures do
  alias Whistle.ClubsFixtures

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
    # Only create a club if club_id is not provided in attrs
    default_attrs =
      case Map.get(attrs, :club_id) do
        nil ->
          club = ClubsFixtures.club_fixture()
          %{club_id: club.id}

        _ ->
          %{}
      end

    {:ok, user} =
      attrs
      |> Enum.into(default_attrs)
      |> valid_user_attributes()
      |> Whistle.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
