defmodule MuddleWeb.RoomLive.Manage do
  use MuddleWeb, :live_view

  alias Muddle.Rooms

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Rooms.get_room_by_slug(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Room not found.") |> push_navigate(to: ~p"/rooms")}

      room ->
        scope = socket.assigns.current_scope

        if Rooms.role(scope, room) == :owner do
          {:ok,
           socket
           |> assign(:page_title, room.name)
           |> assign(:room, room)
           |> stream(:guest_links, Rooms.list_guest_links(scope, room))}
        else
          {:ok,
           socket
           |> put_flash(:error, "You don't manage that room.")
           |> push_navigate(to: ~p"/rooms")}
        end
    end
  end

  @impl true
  def handle_event("create_guest_link", _, socket) do
    case Rooms.create_guest_link(socket.assigns.current_scope, socket.assigns.room) do
      {:ok, link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Guest link created.")
         |> stream_insert(:guest_links, link, at: 0)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create guest link.")}
    end
  end

  def handle_event("revoke_guest_link", %{"id" => id}, socket) do
    link =
      socket.assigns.current_scope
      |> Rooms.list_guest_links(socket.assigns.room)
      |> Enum.find(&(to_string(&1.id) == id))

    case link && Rooms.revoke_guest_link(socket.assigns.current_scope, link) do
      {:ok, revoked} -> {:noreply, stream_insert(socket, :guest_links, revoked)}
      _ -> {:noreply, put_flash(socket, :error, "Could not revoke guest link.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <header class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-2xl font-bold">{@room.name}</h1>
          <p :if={@room.topic} class="text-sm opacity-70">{@room.topic}</p>
        </div>
        <.link navigate={~p"/r/#{@room.slug}"} class="btn btn-primary btn-sm">
          <.icon name="hero-video-camera-micro" class="size-4" /> Open call
        </.link>
      </header>

      <section class="border border-base-300 rounded-box p-4 bg-base-200 mb-6">
        <h2 class="font-semibold mb-1">Direct join link</h2>
        <p class="text-sm opacity-70 mb-2">
          Share this link with members of the room (registered users you've added).
        </p>
        <code class="block text-xs font-mono">{url(~p"/r/#{@room.slug}")}</code>
      </section>

      <section class="border border-base-300 rounded-box p-4 bg-base-200">
        <header class="flex items-center justify-between mb-3">
          <div>
            <h2 class="font-semibold">Guest links</h2>
            <p class="text-sm opacity-70">
              Anyone with a guest link can join this call as an anonymous guest.
            </p>
          </div>
          <button type="button" phx-click="create_guest_link" class="btn btn-primary btn-sm">
            <.icon name="hero-plus-micro" class="size-4" /> New guest link
          </button>
        </header>

        <ul id="guest-links" phx-update="stream" class="flex flex-col gap-2">
          <li id="guest-links-empty" class="hidden only:block text-center text-sm opacity-60 py-6">
            No guest links yet.
          </li>
          <li
            :for={{dom_id, link} <- @streams.guest_links}
            id={dom_id}
            class={[
              "border border-base-300 rounded-box p-3 flex items-center gap-3",
              link.revoked_at && "opacity-60"
            ]}
          >
            <div class="flex-1 min-w-0">
              <code class="block text-xs font-mono truncate">
                {url(~p"/g/#{link.token}")}
              </code>
              <p class="text-xs opacity-60 mt-1">
                <%= cond do %>
                  <% link.revoked_at -> %>
                    revoked
                  <% link.expires_at -> %>
                    expires {Calendar.strftime(link.expires_at, "%Y-%m-%d %H:%M")}
                  <% true -> %>
                    no expiry
                <% end %>
              </p>
            </div>
            <%= if is_nil(link.revoked_at) do %>
              <button
                type="button"
                phx-click="revoke_guest_link"
                phx-value-id={link.id}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-x-mark-micro" class="size-4" />
              </button>
            <% end %>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
