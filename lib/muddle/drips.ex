defmodule Muddle.Drips do
  @moduledoc """
  The Drips context — saved bundles of accessory pins (an "outfit").

  A drip belongs to one user and contains zero or more pins, each
  pairing one of that user's accessories with a body keypoint. During
  a call, applying a drip fans out to `Muddle.Rooms.Authority` so each
  pin lights up like the user pinned them one-by-one.
  """

  import Ecto.Query, warn: false

  alias Muddle.Repo
  alias Muddle.Accounts.{Scope, User}
  alias Muddle.Accessories
  alias Muddle.Drips.{Drip, DripPin}
  alias Muddle.Rooms.Authority

  ## Listing / fetching ----------------------------------------------------

  def list_drips(%Scope{user: %User{id: id}}) do
    from(d in Drip,
      where: d.owner_id == ^id,
      order_by: [asc: d.name],
      preload: [pins: :accessory]
    )
    |> Repo.all()
  end

  def list_drips(_), do: []

  def get_drip(%Scope{user: %User{id: id}}, drip_id) do
    case Repo.get_by(Drip, id: drip_id, owner_id: id) do
      nil -> nil
      drip -> Repo.preload(drip, pins: :accessory)
    end
  end

  def get_drip(_, _), do: nil

  ## Creating --------------------------------------------------------------

  @doc """
  Creates a drip with the given pins. `pins` is a list of maps with
  string or atom keys for `:accessory_id`, `:keypoint`, optional
  `:transform`. Pins referencing accessories the user doesn't own are
  silently dropped.
  """
  def create_drip(%Scope{user: %User{id: owner_id}} = scope, attrs, pins) when is_list(pins) do
    owned_accessory_ids =
      scope
      |> Accessories.list_accessories()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    sanitized_pins =
      pins
      |> Enum.map(&normalize_pin/1)
      |> Enum.filter(& &1)
      |> Enum.filter(&MapSet.member?(owned_accessory_ids, &1.accessory_id))
      |> Enum.uniq_by(& &1.keypoint)

    Repo.transaction(fn ->
      with {:ok, drip} <-
             %Drip{owner_id: owner_id}
             |> Drip.create_changeset(attrs)
             |> Repo.insert() do
        Enum.each(sanitized_pins, fn p ->
          %DripPin{drip_id: drip.id}
          |> DripPin.changeset(%{
            accessory_id: p.accessory_id,
            keypoint: p.keypoint,
            transform: p.transform
          })
          |> Repo.insert!()
        end)

        Repo.preload(drip, pins: :accessory)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp normalize_pin(%{accessory_id: aid, keypoint: kp} = p) do
    %{
      accessory_id: to_int(aid),
      keypoint: to_string(kp),
      transform: Map.get(p, :transform, %{})
    }
  end

  defp normalize_pin(%{"accessory_id" => aid, "keypoint" => kp} = p) do
    %{
      accessory_id: to_int(aid),
      keypoint: to_string(kp),
      transform: Map.get(p, "transform", %{})
    }
  end

  defp normalize_pin(_), do: nil

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  ## Updating --------------------------------------------------------------

  def update_drip(%Scope{user: %User{id: id}}, %Drip{owner_id: id} = drip, attrs) do
    drip
    |> Drip.create_changeset(attrs)
    |> Repo.update()
  end

  def update_drip(_, _, _), do: {:error, :forbidden}

  @doc """
  Adds (or replaces, by `keypoint`) a single pin on a drip. Verifies
  the user owns both the drip and the accessory.
  """
  def add_pin(scope, drip, accessory_id, keypoint, transform \\ %{})

  def add_pin(
        %Scope{user: %User{id: user_id}} = scope,
        %Drip{owner_id: user_id} = drip,
        accessory_id,
        keypoint,
        transform
      ) do
    accessory_id = if is_binary(accessory_id), do: String.to_integer(accessory_id), else: accessory_id

    cond do
      not Enum.member?(Accessories.keypoints(), keypoint) ->
        {:error, :invalid_keypoint}

      is_nil(Accessories.get_accessory(scope, accessory_id)) ->
        {:error, :forbidden}

      true ->
        # Upsert on (drip_id, keypoint).
        from(p in DripPin, where: p.drip_id == ^drip.id and p.keypoint == ^keypoint)
        |> Repo.delete_all()

        %DripPin{drip_id: drip.id}
        |> DripPin.changeset(%{
          accessory_id: accessory_id,
          keypoint: keypoint,
          transform: transform
        })
        |> Repo.insert()
    end
  end

  def add_pin(_, _, _, _, _), do: {:error, :forbidden}

  @doc "Removes the pin at the given keypoint from a drip."
  def remove_pin(%Scope{user: %User{id: user_id}}, %Drip{owner_id: user_id} = drip, keypoint) do
    {n, _} =
      from(p in DripPin, where: p.drip_id == ^drip.id and p.keypoint == ^keypoint)
      |> Repo.delete_all()

    {:ok, n}
  end

  def remove_pin(_, _, _), do: {:error, :forbidden}

  ## Deleting --------------------------------------------------------------

  def delete_drip(%Scope{user: %User{id: id}}, %Drip{owner_id: id} = drip), do: Repo.delete(drip)
  def delete_drip(_, _), do: {:error, :forbidden}

  ## Applying --------------------------------------------------------------

  @doc """
  Applies every pin in `drip` to the live `room_id` as the calling
  user. Each pin goes through `Authority.pin_accessory/5`, which
  broadcasts the resulting `{:pin_op, ...}` over PubSub like an
  individual pin would.
  """
  def apply_drip(%Scope{user: %User{id: user_id}}, room_id, %Drip{owner_id: user_id} = drip)
      when is_integer(room_id) do
    drip = Repo.preload(drip, :pins)

    Enum.each(drip.pins, fn p ->
      Authority.pin_accessory(room_id, user_id, p.accessory_id, p.keypoint, p.transform)
    end)

    :ok
  end

  def apply_drip(_, _, _), do: {:error, :forbidden}
end
