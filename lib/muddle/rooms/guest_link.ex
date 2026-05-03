defmodule Muddle.Rooms.GuestLink do
  @moduledoc """
  A revocable, optionally-expiring URL token granting guest access to a
  single room. Visiting `/g/:token` either binds the visitor's session
  to an anonymous user (which is then admitted to the room) or, if the
  visitor is already logged in, redirects them straight to the room.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accounts.User
  alias Muddle.Rooms.Room

  schema "room_guest_links" do
    field :token, :string
    field :note, :string
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :room, Room
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(link, attrs) do
    link
    |> cast(attrs, [:note, :expires_at])
    |> put_token_if_missing()
    |> validate_required([:token, :room_id, :created_by_id])
    |> validate_length(:note, max: 200)
    |> unique_constraint(:token)
  end

  def active?(%__MODULE__{revoked_at: nil, expires_at: nil}), do: true

  def active?(%__MODULE__{revoked_at: nil, expires_at: %DateTime{} = exp}) do
    DateTime.compare(exp, DateTime.utc_now()) == :gt
  end

  def active?(_), do: false

  defp put_token_if_missing(changeset) do
    case get_field(changeset, :token) do
      nil -> put_change(changeset, :token, generate_token())
      _ -> changeset
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end
end
