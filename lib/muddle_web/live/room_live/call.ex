defmodule MuddleWeb.RoomLive.Call do
  use MuddleWeb, :live_view

  alias Muddle.{Accessories, Drips, Rooms}
  alias Muddle.Accessories.Accessory
  alias Muddle.Rooms.Authority
  alias Muddle.Repo
  alias MuddleWeb.Presence

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Rooms.get_room_by_slug(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Room not found.") |> push_navigate(to: ~p"/")}

      room ->
        if scope && scope.user && Rooms.can_join?(scope, room) do
          if connected?(socket) do
            Phoenix.PubSub.subscribe(Muddle.PubSub, Authority.topic(room.id))
            track_presence(room.id, scope.user)
          end

          {:ok, pins} =
            case Authority.pins(room.id) do
              {:ok, list} -> {:ok, list}
              _ -> {:ok, []}
            end

          # Defer the per-pin `push_event` calls so they fire after the
          # JS Call hook has had a chance to register its
          # `handleEvent("muddle:pin", ...)` listener — pushing them
          # straight from `mount` races the hook's `mounted()`.
          if connected?(socket), do: send(self(), :replay_pins)

          socket =
            socket
            |> assign(:page_title, room.name)
            |> assign(:room, room)
            |> assign(:role, Rooms.role(scope, room))
            |> assign(:keypoints, Accessories.keypoints())
            |> assign(:my_accessories, accessories_for(scope))
            |> assign(:peer_id, peer_id(scope.user))
            |> assign(:current_user_id, scope.user.id)
            |> assign(:socket_token, socket_token(scope.user))
            |> assign(:drip_form, to_form(%{"name" => ""}, as: "drip"))
            |> stream(:participants, [], reset: true)
            |> stream(:pins, Enum.map(pins, &pin_for_stream/1), reset: true)
            |> stream(:drips, drips_for(scope), reset: true)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(
             :error,
             "You don't have access to that room. Ask the host for a guest link."
           )
           |> push_navigate(to: ~p"/")}
        end
    end
  end

  defp accessories_for(%{user: %{kind: "registered"}} = scope),
    do: Accessories.list_accessories(scope)

  defp accessories_for(_), do: []

  defp drips_for(%{user: %{kind: "registered"}} = scope), do: Drips.list_drips(scope)
  defp drips_for(_), do: []

  defp peer_id(user), do: "#{user.kind}-#{user.id}"

  defp socket_token(user),
    do: Phoenix.Token.sign(MuddleWeb.Endpoint, "user socket", user.id)

  defp track_presence(room_id, user) do
    Presence.track(self(), Authority.topic(room_id), peer_id(user), %{
      user_id: user.id,
      kind: user.kind,
      display_name:
        user.display_name || (user.email && user.email |> String.split("@") |> hd()) || "guest",
      online_at: System.system_time(:second)
    })
  end

  defp pin_for_stream(pin) do
    %{
      id: "#{pin.user_id}-#{pin.keypoint}",
      user_id: pin.user_id,
      accessory_id: pin.accessory_id,
      keypoint: pin.keypoint,
      transform: pin.transform
    }
  end

  @impl true
  def handle_info({:pin_op, {:pinned, pin}}, socket) do
    payload = pin_payload(pin)

    {:noreply,
     socket
     |> stream_insert(:pins, pin_for_stream(pin))
     |> push_event("muddle:pin", payload)}
  end

  def handle_info({:pin_op, {:unpinned, %{user_id: uid, keypoint: kp}}}, socket) do
    {:noreply,
     socket
     |> stream_delete_by_dom_id(:pins, "pins-#{uid}-#{kp}")
     |> push_event("muddle:unpin", %{user_id: uid, keypoint: kp})}
  end

  def handle_info(:replay_pins, socket) do
    pins =
      case Authority.pins(socket.assigns.room.id) do
        {:ok, list} -> list
        _ -> []
      end

    socket =
      Enum.reduce(pins, socket, fn pin, acc ->
        push_event(acc, "muddle:pin", pin_payload(pin))
      end)

    {:noreply, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket), do: {:noreply, socket}
  def handle_info(_, socket), do: {:noreply, socket}

  defp pin_payload(pin) do
    accessory = Repo.get(Accessory, pin.accessory_id)

    {image_url, calibration} =
      case accessory do
        %Accessory{} = a ->
          {Accessories.image_url(a),
           %{
             scale: a.default_scale || 1.0,
             offset_x: a.default_offset_x || 0.0,
             offset_y: a.default_offset_y || 0.0,
             rotation: a.default_rotation || 0.0
           }}

        nil ->
          {nil, %{scale: 1.0, offset_x: 0.0, offset_y: 0.0, rotation: 0.0}}
      end

    %{
      user_id: pin.user_id,
      keypoint: pin.keypoint,
      accessory_id: pin.accessory_id,
      image_url: image_url,
      calibration: calibration,
      transform: pin.transform || %{}
    }
  end

  @impl true
  def handle_event("pin", %{"accessory_id" => aid, "keypoint" => kp}, socket) do
    user = socket.assigns.current_scope.user

    case Authority.pin_accessory(socket.assigns.room.id, user.id, String.to_integer(aid), kp) do
      {:ok, _pin} -> {:noreply, socket}
      _ -> {:noreply, put_flash(socket, :error, "Could not pin accessory.")}
    end
  end

  def handle_event("unpin", %{"keypoint" => kp}, socket) do
    user = socket.assigns.current_scope.user
    Authority.unpin(socket.assigns.room.id, user.id, kp)
    {:noreply, socket}
  end

  def handle_event("calibrate", params, socket) do
    scope = socket.assigns.current_scope
    accessory_id = params |> Map.fetch!("accessory_id") |> to_integer()

    attrs = %{
      "default_scale" => to_float(params["scale"], 1.0),
      "default_offset_x" => to_float(params["offset_x"], 0.0),
      "default_offset_y" => to_float(params["offset_y"], 0.0),
      "default_rotation" => to_float(params["rotation"], 0.0)
    }

    with %Accessory{} = accessory <- Accessories.get_accessory(scope, accessory_id),
         {:ok, _} <- Accessories.update_calibration(scope, accessory, attrs) do
      # Refresh every live pin that uses this accessory so other
      # participants see the new offsets/scale immediately.
      case Authority.pins(socket.assigns.room.id) do
        {:ok, pins} ->
          for p <- pins, p.accessory_id == accessory_id do
            Phoenix.PubSub.broadcast(
              Muddle.PubSub,
              Authority.topic(socket.assigns.room.id),
              {:pin_op, {:pinned, p}}
            )
          end

        _ ->
          :ok
      end

      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not save calibration.")}
    end
  end

  def handle_event("apply_drip", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Drips.get_drip(scope, String.to_integer(id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Drip not found.")}

      drip ->
        :ok = Drips.apply_drip(scope, socket.assigns.room.id, drip)
        {:noreply, put_flash(socket, :info, "Applied #{drip.name}.")}
    end
  end

  def handle_event("save_drip", %{"drip" => %{"name" => name}}, socket) do
    scope = socket.assigns.current_scope
    user = scope.user

    pins =
      case Authority.pins(socket.assigns.room.id) do
        {:ok, list} -> Enum.filter(list, &(&1.user_id == user.id))
        _ -> []
      end

    cond do
      String.trim(name) == "" ->
        {:noreply, put_flash(socket, :error, "Give the drip a name.")}

      pins == [] ->
        {:noreply, put_flash(socket, :error, "Pin some accessories first.")}

      true ->
        attrs = %{"name" => String.trim(name)}

        pin_attrs =
          Enum.map(pins, fn p ->
            %{accessory_id: p.accessory_id, keypoint: p.keypoint, transform: p.transform || %{}}
          end)

        case Drips.create_drip(scope, attrs, pin_attrs) do
          {:ok, drip} ->
            {:noreply,
             socket
             |> put_flash(:info, "Saved drip “#{drip.name}”.")
             |> stream_insert(:drips, drip)
             |> assign(:drip_form, to_form(%{"name" => ""}, as: "drip"))}

          {:error, %Ecto.Changeset{} = cs} ->
            errs = Enum.map_join(cs.errors, "; ", fn {f, {msg, _}} -> "#{f} #{msg}" end)
            {:noreply, put_flash(socket, :error, "Could not save drip: #{errs}")}
        end
    end
  end

  def handle_event("delete_drip", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Drips.get_drip(scope, String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      drip ->
        case Drips.delete_drip(scope, drip) do
          {:ok, deleted} -> {:noreply, stream_delete(socket, :drips, deleted)}
          _ -> {:noreply, put_flash(socket, :error, "Could not delete drip.")}
        end
    end
  end

  defp to_integer(v) when is_integer(v), do: v
  defp to_integer(v) when is_binary(v), do: String.to_integer(v)

  defp to_float(nil, default), do: default
  defp to_float(v, _) when is_float(v), do: v
  defp to_float(v, _) when is_integer(v), do: v / 1

  defp to_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> default
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div
        id="call-stage"
        phx-hook="Call"
        data-room-slug={@room.slug}
        data-peer-id={@peer_id}
        data-user-id={@current_user_id}
        data-socket-token={@socket_token}
        class="grid grid-cols-1 lg:grid-cols-[1fr_320px] min-h-[calc(100vh-4rem)]"
      >
        <section class="bg-base-300 p-4">
          <header class="flex items-center justify-between mb-3">
            <div>
              <h1 class="text-lg font-bold">{@room.name}</h1>
              <p :if={@room.topic} class="text-xs opacity-70">{@room.topic}</p>
            </div>
            <span class="badge badge-ghost">{@role}</span>
          </header>

          <div
            id="video-tiles"
            phx-update="ignore"
            class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-3 min-h-[60vh]"
          >
            <%!-- video tiles are populated by the Call hook on the client --%>
          </div>
        </section>

        <aside class="bg-base-200 border-l border-base-300 p-4 overflow-y-auto">
          <h2 class="font-semibold mb-2">Pins</h2>
          <ul id="pins" phx-update="stream" class="text-xs space-y-1 mb-4">
            <li id="pins-empty" class="hidden only:block opacity-60">No accessories pinned yet.</li>
            <li
              :for={{dom_id, pin} <- @streams.pins}
              id={dom_id}
              class="flex items-center justify-between gap-2"
            >
              <span class="font-mono opacity-80">
                user {pin.user_id} · {pin.keypoint}
              </span>
              <%= if pin.user_id == @current_scope.user.id do %>
                <button
                  phx-click="unpin"
                  phx-value-keypoint={pin.keypoint}
                  class="btn btn-ghost btn-xs text-error"
                >
                  ×
                </button>
              <% end %>
            </li>
          </ul>

          <%= if @current_scope.user.kind == "registered" do %>
            <h2 class="font-semibold mb-2 mt-2">Drips</h2>
            <ul id="drips" phx-update="stream" class="text-xs space-y-1 mb-2">
              <li id="drips-empty" class="hidden only:block opacity-60">No drips saved yet.</li>
              <li
                :for={{dom_id, drip} <- @streams.drips}
                id={dom_id}
                class="flex items-center justify-between gap-2 border border-base-300 rounded px-2 py-1"
              >
                <span class="truncate">
                  <span class="font-semibold">{drip.name}</span>
                  <span class="opacity-60">· {length(drip.pins)} pins</span>
                </span>
                <span class="flex items-center gap-1">
                  <button
                    phx-click="apply_drip"
                    phx-value-id={drip.id}
                    class="btn btn-primary btn-xs"
                  >
                    Wear
                  </button>
                  <button
                    phx-click="delete_drip"
                    phx-value-id={drip.id}
                    data-confirm={"Delete drip “" <> drip.name <> "”?"}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    ×
                  </button>
                </span>
              </li>
            </ul>

            <.form
              for={@drip_form}
              phx-submit="save_drip"
              class="flex items-center gap-1 mb-4"
            >
              <input
                type="text"
                name="drip[name]"
                value={@drip_form[:name].value}
                placeholder="Save current as drip…"
                class="input input-xs flex-1"
              />
              <button class="btn btn-primary btn-xs">Save</button>
            </.form>
          <% end %>

          <%= if @my_accessories != [] do %>
            <h2 class="font-semibold mb-2">Your accessories</h2>
            <ul class="space-y-2">
              <li
                :for={a <- @my_accessories}
                class="border border-base-300 rounded p-2 flex items-center gap-2"
              >
                <img src={Accessories.image_url(a)} alt={a.name} class="size-10 rounded" />
                <div class="flex-1 min-w-0">
                  <p class="text-sm truncate">{a.name}</p>
                  <form phx-submit="pin" class="flex items-center gap-1">
                    <input type="hidden" name="accessory_id" value={a.id} />
                    <select name="keypoint" class="select select-xs flex-1">
                      <option :for={kp <- @keypoints} value={kp} selected={kp == a.default_keypoint}>
                        {kp}
                      </option>
                    </select>
                    <button class="btn btn-primary btn-xs">Pin</button>
                  </form>
                </div>
              </li>
            </ul>
          <% else %>
            <%= if @current_scope.user.kind == "registered" do %>
              <p class="text-sm opacity-70">
                Upload accessories at <.link navigate={~p"/accessories"} class="link">/accessories</.link>.
              </p>
            <% else %>
              <p class="text-sm opacity-70">
                Sign in to upload accessories.
              </p>
            <% end %>
          <% end %>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
