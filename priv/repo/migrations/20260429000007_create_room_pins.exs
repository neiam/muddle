defmodule Muddle.Repo.Migrations.CreateRoomPins do
  use Ecto.Migration

  def change do
    create table(:room_pins) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :accessory_id, references(:accessories, on_delete: :delete_all), null: false
      add :keypoint, :string, null: false
      add :transform, :map, null: false, default: %{}
      add :pinned_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_pins, [:room_id, :user_id, :keypoint])
    create index(:room_pins, [:room_id])
  end
end
