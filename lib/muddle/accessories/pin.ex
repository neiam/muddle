defmodule Muddle.Accessories.Pin do
  @moduledoc """
  A persistent default pin: when this user joins a call, the
  given accessory is auto-pinned to the named body keypoint.

  Live, in-call pins are tracked transiently by `Muddle.Rooms.Authority`
  and not persisted here.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accessories.Accessory
  alias Muddle.Accounts.User

  @type t :: %__MODULE__{}

  schema "accessory_pins" do
    field :keypoint, :string
    field :transform, :map, default: %{}

    belongs_to :user, User
    belongs_to :accessory, Accessory

    timestamps(type: :utc_datetime)
  end

  def changeset(pin, attrs) do
    pin
    |> cast(attrs, [:user_id, :accessory_id, :keypoint, :transform])
    |> validate_required([:user_id, :accessory_id, :keypoint])
    |> validate_inclusion(:keypoint, Muddle.Accessories.keypoints())
    |> unique_constraint([:user_id, :keypoint])
  end
end
