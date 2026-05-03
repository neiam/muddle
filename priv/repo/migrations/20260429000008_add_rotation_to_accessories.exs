defmodule Muddle.Repo.Migrations.AddRotationToAccessories do
  use Ecto.Migration

  def change do
    alter table(:accessories) do
      # Static rotation offset, in radians, baked into the accessory.
      # Useful when the source image was drawn slightly tilted, or to
      # tweak how an accessory sits on the head independent of head roll.
      add :default_rotation, :float, null: false, default: 0.0
    end
  end
end
