defmodule Muddle.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accounts.User
  alias Muddle.Rooms.{Membership, GuestLink}

  schema "rooms" do
    field :slug, :string
    field :name, :string
    field :topic, :string
    field :max_participants, :integer, default: 12
    field :archived_at, :utc_datetime

    belongs_to :owner, User
    has_many :memberships, Membership
    has_many :guest_links, GuestLink

    timestamps(type: :utc_datetime)
  end

  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :topic, :max_participants])
    |> put_friendly_name_if_blank()
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:topic, max: 200)
    |> validate_number(:max_participants, greater_than: 0, less_than_or_equal_to: 64)
    |> put_slug_if_missing()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  def update_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :topic, :max_participants, :archived_at])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:topic, max: 200)
    |> validate_number(:max_participants, greater_than: 0, less_than_or_equal_to: 64)
  end

  defp put_slug_if_missing(changeset) do
    case get_field(changeset, :slug) do
      nil -> put_change(changeset, :slug, generate_slug())
      _ -> changeset
    end
  end

  defp put_friendly_name_if_blank(changeset) do
    case get_field(changeset, :name) do
      name when is_binary(name) and name != "" ->
        changeset

      _ ->
        put_change(changeset, :name, FriendlyID.generate(2, separator: " "))
    end
  end

  # Slug stays short and URL-safe for the call URL — `/r/<slug>` —
  # while the human-friendly name comes from FriendlyID.
  defp generate_slug do
    :crypto.strong_rand_bytes(9)
    |> Base.url_encode64(padding: false)
    |> String.downcase()
  end
end
