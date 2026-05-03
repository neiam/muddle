defmodule Muddle.Repo do
  use Ecto.Repo,
    otp_app: :muddle,
    adapter: Ecto.Adapters.Postgres
end
