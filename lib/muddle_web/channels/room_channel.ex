defmodule MuddleWeb.RoomChannel do
  @moduledoc """
  Bridge between the browser's WebRTC client and `Muddle.Media.RoomEngine`
  for a single peer (one participant in one room).

  The browser sends `"media_event"` messages carrying opaque SDP/ICE
  payloads; we hand them off to the engine. The engine sends back
  Membrane media events as Erlang messages, which we translate into
  channel pushes the JS client understands.
  """
  use MuddleWeb, :channel

  alias Muddle.Accounts.User
  alias Muddle.Media.RoomEngine
  alias Muddle.Rooms

  @impl true
  def join("room:" <> slug, _params, socket) do
    scope = socket.assigns[:scope]

    with %_{} = room <- Rooms.get_room_by_slug(slug),
         true <- Rooms.can_join?(scope, room) do
      peer_id = peer_id(scope.user, socket)

      # Best-effort: if the Membrane engine isn't healthy yet (no SDK
      # wired on the client, missing native deps in dev, etc) we still
      # let the channel join so the LV presence/pin features work.
      case RoomEngine.add_peer(room.id, peer_id, self()) do
        :ok -> :ok
        other -> require Logger; Logger.warning("[muddle] add_peer failed: #{inspect(other)}")
      end

      {:ok,
       socket
       |> assign(:room_id, room.id)
       |> assign(:peer_id, peer_id)}
    else
      _ -> {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_in("media_event", %{"event" => event}, socket) do
    :ok = RoomEngine.media_event(socket.assigns.room_id, socket.assigns.peer_id, event)
    {:noreply, socket}
  end

  # Membrane RTC Engine pushes media events back to the channel pid.
  @impl true
  def handle_info({:media_event, event}, socket) do
    push(socket, "media_event", %{event: event})
    {:noreply, socket}
  end

  def handle_info({:end_of_stream, _track}, socket), do: {:noreply, socket}
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    if rid = socket.assigns[:room_id] do
      RoomEngine.remove_peer(rid, socket.assigns.peer_id)
    end

    :ok
  end

  defp peer_id(%User{id: id, kind: kind}, _socket), do: "#{kind}-#{id}"
  defp peer_id(_, socket), do: "anon-#{socket.id}"
end
