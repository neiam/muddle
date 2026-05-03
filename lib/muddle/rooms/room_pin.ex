defmodule Muddle.Rooms.RoomPin do
  @moduledoc """
  A live, in-call accessory pin. Persisted so pins survive server
  restarts, the Authority's hibernate window, and browser reloads.

  Distinct from `Muddle.Accessories.Pin`, which is the user's saved
  default outfit (unscoped to a room).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accessories.Accessory
  alias Muddle.Accounts.User
  alias Muddle.Rooms.Room

  schema "room_pins" do
    field :keypoint, :string
    field :transform, :map, default: %{}
    field :pinned_at, :utc_datetime

    belongs_to :room, Room
    belongs_to :user, User
    belongs_to :accessory, Accessory

    timestamps(type: :utc_datetime)
  end

  def changeset(pin, attrs) do
    pin
    |> cast(attrs, [:keypoint, :transform, :pinned_at, :accessory_id])
    |> validate_required([:room_id, :user_id, :keypoint, :accessory_id, :pinned_at])
    |> unique_constraint([:room_id, :user_id, :keypoint])
  end
end
