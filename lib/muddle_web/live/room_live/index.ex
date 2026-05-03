defmodule MuddleWeb.RoomLive.Index do
  use MuddleWeb, :live_view

  alias Muddle.Rooms

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Rooms")
     |> assign(:form, to_form(%{"name" => "", "topic" => ""}, as: "room"))
     |> stream(:rooms, Rooms.list_rooms_for(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("create", %{"room" => attrs}, socket) do
    case Rooms.create_room(socket.assigns.current_scope, attrs) do
      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Room \"#{room.name}\" created.")
         |> stream_insert(:rooms, room, at: 0)
         |> push_patch(to: ~p"/rooms")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "room"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <header class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold">Rooms</h1>
          <p class="text-sm opacity-70">Spin up a video call and invite people in.</p>
        </div>
      </header>

      <.form
        for={@form}
        phx-submit="create"
        class="border border-base-300 rounded-box p-4 mb-6 bg-base-200 grid gap-3 sm:grid-cols-[1fr_2fr_auto]"
      >
        <.input field={@form[:name]} placeholder="Leave blank for a friendly name" />
        <.input field={@form[:topic]} placeholder="Topic (optional)" />
        <.button class="btn btn-primary">Create room</.button>
      </.form>

      <ul id="rooms" phx-update="stream" class="flex flex-col gap-2">
        <li id="rooms-empty" class="hidden only:block text-center text-sm opacity-60 py-8">
          You haven't created any rooms yet.
        </li>
        <li
          :for={{dom_id, room} <- @streams.rooms}
          id={dom_id}
          class="border border-base-300 rounded-box p-3 flex items-center gap-3 bg-base-200"
        >
          <div class="flex-1 min-w-0">
            <p class="font-semibold truncate">{room.name}</p>
            <p :if={room.topic} class="text-xs opacity-70 truncate">{room.topic}</p>
            <code class="block mt-1 text-xs font-mono opacity-60 truncate">
              {url(~p"/r/#{room.slug}")}
            </code>
          </div>
          <div class="flex items-center gap-1">
            <.link navigate={~p"/r/#{room.slug}"} class="btn btn-primary btn-sm">
              <.icon name="hero-video-camera-micro" class="size-4" /> Join
            </.link>
            <.link navigate={~p"/rooms/#{room.slug}/manage"} class="btn btn-ghost btn-sm">
              <.icon name="hero-cog-6-tooth-micro" class="size-4" />
            </.link>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
