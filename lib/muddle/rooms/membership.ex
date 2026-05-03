defmodule Muddle.Rooms.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accounts.User
  alias Muddle.Rooms.Room

  schema "room_memberships" do
    belongs_to :room, Room
    belongs_to :user, User

    field :role, :string, default: "member"

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:room_id, :user_id, :role])
    |> validate_required([:room_id, :user_id])
    |> validate_inclusion(:role, ~w(member moderator))
    |> unique_constraint([:room_id, :user_id])
  end
end
