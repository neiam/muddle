defmodule Muddle.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :muddle

  alias Muddle.Accounts.User
  alias Muddle.Repo

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Bootstraps an initial user with the given email + password and stamps
  `confirmed_at` so the account can log in immediately. Idempotent: if a
  user with that email already exists the password is rotated and
  confirmation is re-stamped.

  Pass either binaries or atoms (atoms get coerced via `to_string/1`).
  """
  @spec init(String.t() | atom(), String.t() | atom()) :: {:ok, User.t()} | {:error, term()}
  def init(email, password) do
    load_app()

    email = to_string(email)
    password = to_string(password)

    [repo | _] = repos()

    {:ok, result, _started} =
      Ecto.Migrator.with_repo(repo, fn _ -> upsert_user(email, password) end)

    case result do
      {:ok, %User{} = user} ->
        IO.puts("✓ ready: #{user.email}")
        {:ok, user}

      {:error, changeset} ->
        IO.puts("✗ failed: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc false
  def upsert_user(email, password) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(User, email: email) do
      nil ->
        %User{kind: "registered"}
        |> User.email_changeset(%{email: email}, validate_unique: true)
        |> User.password_changeset(%{password: password})
        |> Ecto.Changeset.put_change(:confirmed_at, now)
        |> Repo.insert()

      %User{} = user ->
        user
        |> User.password_changeset(%{password: password})
        |> Ecto.Changeset.put_change(:confirmed_at, now)
        |> Repo.update()
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
