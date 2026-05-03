defmodule Muddle.Drips.Drip do
  use Ecto.Schema
  import Ecto.Changeset

  alias Muddle.Accounts.User
  alias Muddle.Drips.DripPin

  schema "drips" do
    field :name, :string
    belongs_to :owner, User
    has_many :pins, DripPin, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def create_changeset(drip, attrs) do
    drip
    |> cast(attrs, [:name])
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint([:owner_id, :name])
  end
end
