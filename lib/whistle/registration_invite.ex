defmodule Whistle.RegistrationInvite do
  @moduledoc """
  Validates the shared invitation code required for public registration.
  """

  @config_key :registration_invite_code

  def valid_code?(provided_code) when is_binary(provided_code) do
    expected_code = Application.get_env(:whistle, @config_key)

    with true <- configured_code?(expected_code),
         expected_code <- String.trim(expected_code),
         provided_code <- String.trim(provided_code),
         true <- byte_size(provided_code) == byte_size(expected_code) do
      Plug.Crypto.secure_compare(provided_code, expected_code)
    else
      _ -> false
    end
  end

  def valid_code?(_provided_code), do: false

  defp configured_code?(code) when is_binary(code), do: String.trim(code) != ""
  defp configured_code?(_code), do: false
end
