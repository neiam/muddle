defmodule Muddle.Accessories.Accessory do
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accounts.User

  schema "accessories" do
    field :name, :string
    field :description, :string
    field :image_path, :string
    field :content_type, :string
    field :default_keypoint, :string
    field :public, :boolean, default: false
    field :deleted_at, :utc_datetime

    # Per-accessory calibration applied on top of the keypoint layout
    # so e.g. a hat with a brim sits right on the head.
    field :default_scale, :float, default: 1.0
    field :default_offset_x, :float, default: 0.0
    field :default_offset_y, :float, default: 0.0
    # Rotation offset in radians. Composed with the live head/body roll
    # at render time.
    field :default_rotation, :float, default: 0.0

    belongs_to :owner, User

    timestamps(type: :utc_datetime)
  end

  @calibration_fields [
    :default_scale,
    :default_offset_x,
    :default_offset_y,
    :default_rotation
  ]

  def create_changeset(accessory, attrs) do
    accessory
    |> cast(
      attrs,
      [:name, :description, :image_path, :content_type, :default_keypoint, :public] ++
        @calibration_fields
    )
    |> validate_required([:name, :owner_id, :image_path])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:default_keypoint, Muddle.Accessories.keypoints() ++ [nil])
    |> validate_calibration()
  end

  def update_changeset(accessory, attrs) do
    accessory
    |> cast(attrs, [:name, :description, :default_keypoint, :public] ++ @calibration_fields)
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:default_keypoint, Muddle.Accessories.keypoints() ++ [nil])
    |> validate_calibration()
  end

  def calibration_changeset(accessory, attrs) do
    accessory
    |> cast(attrs, @calibration_fields)
    |> validate_calibration()
  end

  defp validate_calibration(changeset) do
    changeset
    |> validate_number(:default_scale, greater_than: 0.05, less_than: 10.0)
    |> validate_number(:default_offset_x, greater_than_or_equal_to: -2.0, less_than_or_equal_to: 2.0)
    |> validate_number(:default_offset_y, greater_than_or_equal_to: -2.0, less_than_or_equal_to: 2.0)
    # Rotation in radians; clamp to two full turns to keep things sane.
    |> validate_number(:default_rotation,
      greater_than_or_equal_to: -2 * :math.pi(),
      less_than_or_equal_to: 2 * :math.pi()
    )
  end
end
