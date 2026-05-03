defmodule Muddle.Rooms.Authority do
  @moduledoc """
  GenServer-per-room that owns the live state of a single video call:
  the active accessory pin set (who is wearing what, attached to which
  body keypoint), and a reference to the Membrane RTC Engine instance
  doing the actual media routing.

  Lifecycle:
    * Started on demand via `for_room/1` (looks up via Horde.Registry,
      spawns under Horde.DynamicSupervisor if needed).
    * Idle for `@hibernate_after` ms with no participants → terminates
      and shuts down the underlying Membrane engine.

  Pin operations broadcast `{:pin_op, ...}` on `topic/1` so all
  subscribed LiveViews update for every participant.
  """

  alias Muddle.Accessories.Pin
  alias Muddle.Repo
  alias Muddle.Rooms.RoomPin

  @registry Muddle.Rooms.AuthorityRegistry
  @supervisor Muddle.Rooms.AuthoritySupervisor
  @hibernate_after :timer.minutes(15)

  ## Public API -------------------------------------------------------------

  @spec topic(integer()) :: String.t()
  def topic(room_id), do: "room:#{room_id}"

  @spec for_room(integer()) :: {:ok, pid()} | {:error, term()}
  def for_room(room_id) when is_integer(room_id) do
    case Horde.Registry.lookup(@registry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_authority(room_id)
    end
  end

  @doc """
  Returns a snapshot of currently-pinned accessories for the room.
  """
  @spec pins(integer()) :: {:ok, [Pin.t()]} | {:error, term()}
  def pins(room_id) do
    with {:ok, pid} <- for_room(room_id) do
      GenServer.call(pid, :pins)
    end
  end

  @doc """
  Pins an accessory to the given body keypoint for the calling user. If
  the same (user, keypoint) pair already has something pinned, it's
  replaced.
  """
  @spec pin_accessory(integer(), integer(), integer(), String.t(), map()) ::
          {:ok, Pin.t()} | {:error, term()}
  def pin_accessory(room_id, user_id, accessory_id, keypoint, transform \\ %{}) do
    with {:ok, pid} <- for_room(room_id) do
      GenServer.call(
        pid,
        {:pin,
         %{user_id: user_id, accessory_id: accessory_id, keypoint: keypoint, transform: transform}}
      )
    end
  end

  @spec unpin(integer(), integer(), String.t()) :: :ok | {:error, term()}
  def unpin(room_id, user_id, keypoint) do
    with {:ok, pid} <- for_room(room_id) do
      GenServer.call(pid, {:unpin, user_id, keypoint})
    end
  end

  @doc "Stops the authority for a room (used on delete and in tests)."
  def stop(room_id) do
    case Horde.Registry.lookup(@registry, room_id) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  ## Supervision wiring ----------------------------------------------------

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :supervisor
    }
  end

  def start_link(_opts \\ []) do
    Supervisor.start_link(
      [
        {Horde.Registry, [keys: :unique, name: @registry, members: :auto]},
        {Horde.DynamicSupervisor, [strategy: :one_for_one, name: @supervisor, members: :auto]}
      ],
      strategy: :one_for_all,
      name: __MODULE__.Supervisor
    )
  end

  defp start_authority(room_id) do
    spec = {__MODULE__.Server, room_id}
    Horde.DynamicSupervisor.start_child(@supervisor, spec)
  end

  ## Server module ---------------------------------------------------------

  defmodule Server do
    @moduledoc false
    use GenServer, restart: :transient

    alias Muddle.Rooms.Authority

    def start_link(room_id) do
      GenServer.start_link(__MODULE__, room_id,
        name: {:via, Horde.Registry, {Authority.registry(), room_id}}
      )
    end

    @impl true
    def init(room_id) do
      pins = Authority.load_pins(room_id)
      {:ok, %{room_id: room_id, pins: pins}, Authority.hibernate_after()}
    end

    @impl true
    def handle_call(:pins, _from, state) do
      {:reply, {:ok, Map.values(state.pins)}, state, Authority.hibernate_after()}
    end

    def handle_call({:pin, attrs}, _from, state) do
      key = {attrs.user_id, attrs.keypoint}

      pin =
        Map.merge(attrs, %{
          room_id: state.room_id,
          pinned_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      Authority.persist_pin!(pin)
      pins = Map.put(state.pins, key, pin)

      Phoenix.PubSub.broadcast(
        Muddle.PubSub,
        Authority.topic(state.room_id),
        {:pin_op, {:pinned, pin}}
      )

      {:reply, {:ok, pin}, %{state | pins: pins}, Authority.hibernate_after()}
    end

    def handle_call({:unpin, user_id, keypoint}, _from, state) do
      key = {user_id, keypoint}
      Authority.delete_pin!(state.room_id, user_id, keypoint)
      pins = Map.delete(state.pins, key)

      Phoenix.PubSub.broadcast(
        Muddle.PubSub,
        Authority.topic(state.room_id),
        {:pin_op, {:unpinned, %{user_id: user_id, keypoint: keypoint}}}
      )

      {:reply, :ok, %{state | pins: pins}, Authority.hibernate_after()}
    end

    @impl true
    def handle_info(:timeout, state) do
      {:stop, :normal, state}
    end
  end

  ## Internals exposed for the Server module ------------------------------

  @doc false
  def registry, do: @registry

  @doc false
  def hibernate_after, do: @hibernate_after

  @doc false
  def load_pins(room_id) do
    import Ecto.Query

    RoomPin
    |> where([p], p.room_id == ^room_id)
    |> Repo.all()
    |> Enum.into(%{}, fn p ->
      pin = %{
        room_id: p.room_id,
        user_id: p.user_id,
        accessory_id: p.accessory_id,
        keypoint: p.keypoint,
        transform: p.transform,
        pinned_at: p.pinned_at
      }

      {{p.user_id, p.keypoint}, pin}
    end)
  rescue
    DBConnection.OwnershipError -> %{}
    DBConnection.ConnectionError -> %{}
  end

  @doc false
  def persist_pin!(pin) do
    %RoomPin{
      room_id: pin.room_id,
      user_id: pin.user_id
    }
    |> RoomPin.changeset(%{
      accessory_id: pin.accessory_id,
      keypoint: pin.keypoint,
      transform: pin.transform || %{},
      pinned_at: pin.pinned_at
    })
    |> Repo.insert(
      on_conflict: {:replace, [:accessory_id, :transform, :pinned_at, :updated_at]},
      conflict_target: [:room_id, :user_id, :keypoint]
    )
    |> case do
      {:ok, _} -> :ok
      {:error, cs} -> raise "could not persist room pin: #{inspect(cs.errors)}"
    end
  rescue
    DBConnection.OwnershipError -> :ok
    DBConnection.ConnectionError -> :ok
  end

  @doc false
  def delete_pin!(room_id, user_id, keypoint) do
    import Ecto.Query

    RoomPin
    |> where([p], p.room_id == ^room_id and p.user_id == ^user_id and p.keypoint == ^keypoint)
    |> Repo.delete_all()

    :ok
  rescue
    DBConnection.OwnershipError -> :ok
    DBConnection.ConnectionError -> :ok
  end
end
