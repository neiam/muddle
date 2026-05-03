defmodule Muddle.Repo.Migrations.CreateDrips do
  use Ecto.Migration

  def change do
    create table(:drips) do
      add :name, :string, null: false
      add :owner_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:drips, [:owner_id])
    create unique_index(:drips, [:owner_id, :name])

    create table(:drip_pins) do
      add :drip_id, references(:drips, on_delete: :delete_all), null: false
      add :accessory_id, references(:accessories, on_delete: :delete_all), null: false
      add :keypoint, :string, null: false
      add :transform, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:drip_pins, [:drip_id])
    create unique_index(:drip_pins, [:drip_id, :keypoint])
  end
end
