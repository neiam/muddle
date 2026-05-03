defmodule Muddle.Drips.DripPin do
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accessories.Accessory
  alias Muddle.Drips.Drip

  schema "drip_pins" do
    field :keypoint, :string
    field :transform, :map, default: %{}

    belongs_to :drip, Drip
    belongs_to :accessory, Accessory

    timestamps(type: :utc_datetime)
  end

  def changeset(pin, attrs) do
    pin
    |> cast(attrs, [:accessory_id, :keypoint, :transform])
    |> validate_required([:drip_id, :accessory_id, :keypoint])
    |> validate_inclusion(:keypoint, Muddle.Accessories.keypoints())
    |> unique_constraint([:drip_id, :keypoint])
  end
end
