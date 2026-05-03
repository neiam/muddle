defmodule MuddleWeb.DripLive.Index do
  use MuddleWeb, :live_view

  alias Muddle.Accessories
  alias Muddle.Drips

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Drips")
     |> assign(:create_form, to_form(%{"name" => ""}, as: "drip"))
     |> stream(:drips, Drips.list_drips(scope))}
  end

  @impl true
  def handle_event("create", %{"drip" => %{"name" => name}}, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, put_flash(socket, :error, "Give the drip a name.")}

      name ->
        case Drips.create_drip(socket.assigns.current_scope, %{"name" => name}, []) do
          {:ok, drip} ->
            {:noreply,
             socket
             |> put_flash(:info, "Created “#{drip.name}”.")
             |> stream_insert(:drips, drip, at: 0)
             |> assign(:create_form, to_form(%{"name" => ""}, as: "drip"))
             |> push_navigate(to: ~p"/drips/#{drip.id}/edit")}

          {:error, %Ecto.Changeset{} = cs} ->
            errs = Enum.map_join(cs.errors, "; ", fn {f, {msg, _}} -> "#{f} #{msg}" end)
            {:noreply, put_flash(socket, :error, "Could not create: #{errs}")}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Drips.get_drip(scope, String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      drip ->
        case Drips.delete_drip(scope, drip) do
          {:ok, deleted} ->
            {:noreply,
             socket
             |> put_flash(:info, "Deleted “#{deleted.name}”.")
             |> stream_delete(:drips, deleted)}

          _ ->
            {:noreply, put_flash(socket, :error, "Could not delete.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <header class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold">Drips</h1>
          <p class="text-sm opacity-70">Outfits — bundles of accessories you can pin in one click.</p>
        </div>
      </header>

      <.form
        for={@create_form}
        phx-submit="create"
        class="border border-base-300 rounded-box p-4 mb-6 bg-base-200 grid gap-3 sm:grid-cols-[1fr_auto]"
      >
        <input
          type="text"
          name="drip[name]"
          value={@create_form[:name].value}
          placeholder="New drip name"
          class="input input-bordered"
        />
        <.button class="btn btn-primary">Create drip</.button>
      </.form>

      <ul id="drips" phx-update="stream" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <li id="drips-empty" class="hidden only:block col-span-full text-center text-sm opacity-60 py-8">
          No drips yet. Create one above, or save the current pin set as a drip from inside a call.
        </li>
        <li
          :for={{dom_id, drip} <- @streams.drips}
          id={dom_id}
          class="border border-base-300 rounded-box p-3 bg-base-200"
        >
          <div class="flex items-center justify-between mb-2">
            <p class="font-semibold truncate">{drip.name}</p>
            <span class="text-xs opacity-60">{length(drip.pins)} pins</span>
          </div>

          <ul class="flex flex-wrap gap-1 mb-3 min-h-[2.5rem]">
            <li :for={pin <- drip.pins} class="flex items-center gap-1 bg-base-300 rounded p-1">
              <img
                src={Accessories.image_url(pin.accessory)}
                alt={pin.accessory.name}
                class="size-8 rounded object-contain bg-black/10"
              />
              <span class="text-xs opacity-70">{pin.keypoint}</span>
            </li>
          </ul>

          <div class="flex items-center gap-1">
            <.link navigate={~p"/drips/#{drip.id}/edit"} class="btn btn-ghost btn-xs">
              <.icon name="hero-pencil-square-micro" class="size-4" /> Edit
            </.link>
            <button
              phx-click="delete"
              phx-value-id={drip.id}
              data-confirm={"Delete drip “" <> drip.name <> "”?"}
              class="btn btn-ghost btn-xs text-error ml-auto"
            >
              <.icon name="hero-trash-micro" class="size-4" />
            </button>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
