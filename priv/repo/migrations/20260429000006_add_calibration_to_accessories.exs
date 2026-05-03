defmodule Muddle.Repo.Migrations.AddCalibrationToAccessories do
  use Ecto.Migration

  def change do
    alter table(:accessories) do
      # Multiplier on the keypoint's default size. 1.0 = no change.
      add :default_scale, :float, null: false, default: 1.0
      # Offsets from the keypoint position, expressed as fractions of
      # the tile width/height. e.g. 0.05 = 5% right of the keypoint.
      add :default_offset_x, :float, null: false, default: 0.0
      add :default_offset_y, :float, null: false, default: 0.0
    end
  end
end
