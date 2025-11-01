defmodule Whistle.Repo do
  use Ecto.Repo,
    otp_app: :whistle,
    adapter: Ecto.Adapters.Postgres
end
