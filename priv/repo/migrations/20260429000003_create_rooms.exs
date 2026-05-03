defmodule Muddle.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :topic, :string
      add :max_participants, :integer, null: false, default: 12
      add :archived_at, :utc_datetime
      add :owner_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rooms, [:slug])
    create index(:rooms, [:owner_id])

    create table(:room_memberships) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_memberships, [:room_id, :user_id])
    create index(:room_memberships, [:user_id])

    create table(:room_guest_links) do
      add :token, :string, null: false
      add :note, :string
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_guest_links, [:token])
    create index(:room_guest_links, [:room_id])
  end
end
