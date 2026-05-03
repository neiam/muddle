defmodule Muddle.Repo.Migrations.CreateAccessories do
  use Ecto.Migration

  def change do
    create table(:accessories) do
      add :name, :string, null: false
      add :description, :string
      add :image_path, :string, null: false
      add :content_type, :string
      add :default_keypoint, :string
      add :public, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime
      add :owner_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:accessories, [:owner_id])

    create table(:accessory_pins) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :accessory_id, references(:accessories, on_delete: :delete_all), null: false
      add :keypoint, :string, null: false
      add :transform, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accessory_pins, [:user_id, :keypoint])
    create index(:accessory_pins, [:accessory_id])
  end
end
