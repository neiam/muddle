defmodule Muddle.Media.RoomEngine do
  @moduledoc """
  Per-room wrapper around the Membrane RTC Engine. Each call gets its
  own engine instance — Membrane does the heavy lifting (RTP, DTLS,
  SDP munging, simulcast forwarding, recording, etc.). The engine is
  registered under `Muddle.Media.RoomEngineRegistry` keyed by room id
  and supervised by `Muddle.Media.RoomEngineSupervisor`.

  Browser clients establish a WebRTC peer connection through the
  `MuddleWeb.RoomChannel` channel, which forwards SDP offers/answers
  and ICE candidates to the engine via the WebRTC endpoint.

  The engine stays alive for as long as the room has at least one
  participant. The `Muddle.Rooms.Authority` triggers `start/1` when the
  first participant joins and `stop/1` when the last one leaves.
  """

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.WebRTC

  @registry Muddle.Media.RoomEngineRegistry
  @supervisor Muddle.Media.RoomEngineSupervisor

  @doc "Returns (lazily starting) the engine pid for `room_id`."
  @spec for_room(integer()) :: {:ok, pid()} | {:error, term()}
  def for_room(room_id) when is_integer(room_id) do
    case Horde.Registry.lookup(@registry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> start(room_id)
    end
  end

  @doc "Stops the engine for `room_id`."
  def stop(room_id) do
    case Horde.Registry.lookup(@registry, room_id) do
      [{pid, _}] -> Engine.terminate(pid, asynchronous?: true)
      [] -> :ok
    end
  end

  @doc """
  Adds a WebRTC endpoint to the engine for the given participant. The
  channel pid receives Membrane media events and is expected to
  marshal them to the browser over the Phoenix Channel.

  Note: only the fields required by the current `Membrane.RTC.Engine.Endpoint.WebRTC`
  struct are set. STUN/TURN configuration is supplied via the
  `integrated_turn_options` keyword (see `ice_options/0`); add a real
  TURN server in production by setting `MUDDLE_ICE_SERVERS` and
  expanding the keyword we build here.
  """
  @spec add_peer(integer(), String.t(), pid()) :: {:ok, term()} | {:error, term()}
  def add_peer(room_id, peer_id, channel_pid) do
    with {:ok, engine} <- for_room(room_id) do
      endpoint = %WebRTC{
        rtc_engine: engine,
        ice_name: peer_id,
        owner: channel_pid,
        integrated_turn_options: ice_options(),
        metadata: %{peer_id: peer_id}
      }

      Engine.add_endpoint(engine, endpoint, id: peer_id)
    end
  end

  @doc "Removes a peer from the engine (e.g. on disconnect)."
  def remove_peer(room_id, peer_id) do
    case Horde.Registry.lookup(@registry, room_id) do
      [{pid, _}] -> Engine.remove_endpoint(pid, peer_id)
      [] -> :ok
    end
  end

  @doc """
  Forwards a media event from the browser channel into the engine for
  the named peer. `event` is the opaque JSON blob the JS client
  produced (see `MembraneWebRTC` JS lib).
  """
  def media_event(room_id, peer_id, event) do
    with {:ok, engine} <- for_room(room_id) do
      Engine.message_endpoint(engine, peer_id, {:media_event, event})
    end
  end

  ## Supervision -----------------------------------------------------------

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

  defp start(room_id) do
    spec = %{
      id: {Engine, room_id},
      start:
        {Engine, :start_link,
         [
           [id: "muddle-room-#{room_id}"],
           [name: {:via, Horde.Registry, {@registry, room_id}}]
         ]},
      restart: :transient
    }

    Horde.DynamicSupervisor.start_child(@supervisor, spec)
  end

  defp ice_options do
    Application.get_env(:muddle, __MODULE__, [])[:integrated_turn_options] || []
  end
end
