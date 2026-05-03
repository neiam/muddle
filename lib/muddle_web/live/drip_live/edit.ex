defmodule MuddleWeb.DripLive.Edit do
  use MuddleWeb, :live_view

  alias Muddle.Accessories
  alias Muddle.Drips

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Drips.get_drip(scope, String.to_integer(id)) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Drip not found.")
         |> push_navigate(to: ~p"/drips")}

      drip ->
        accessories = Accessories.list_accessories(scope)

        {:ok,
         socket
         |> assign(:page_title, "Edit · " <> drip.name)
         |> assign(:drip, drip)
         |> assign(:keypoints, Accessories.keypoints())
         |> assign(:accessories, accessories)
         |> assign(:rename_form, to_form(%{"name" => drip.name}, as: "drip"))
         |> assign(:add_form, default_add_form(accessories))}
    end
  end

  defp default_add_form([]), do: to_form(%{"accessory_id" => "", "keypoint" => "head"}, as: "pin")

  defp default_add_form([%{id: id} | _]),
    do: to_form(%{"accessory_id" => to_string(id), "keypoint" => "head"}, as: "pin")

  @impl true
  def handle_event("rename", %{"drip" => %{"name" => name}}, socket) do
    case Drips.update_drip(socket.assigns.current_scope, socket.assigns.drip, %{"name" => name}) do
      {:ok, drip} ->
        {:noreply,
         socket
         |> put_flash(:info, "Renamed.")
         |> assign(:drip, reload(socket.assigns.current_scope, drip.id))
         |> assign(:rename_form, to_form(%{"name" => drip.name}, as: "drip"))}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :rename_form, to_form(cs, as: "drip"))}
    end
  end

  def handle_event("add_pin", %{"pin" => %{"accessory_id" => aid, "keypoint" => kp}}, socket) do
    scope = socket.assigns.current_scope

    case Drips.add_pin(scope, socket.assigns.drip, aid, kp) do
      {:ok, _pin} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pin set.")
         |> assign(:drip, reload(scope, socket.assigns.drip.id))
         |> assign(:add_form, default_add_form(socket.assigns.accessories))}

      {:error, :invalid_keypoint} ->
        {:noreply, put_flash(socket, :error, "Invalid keypoint.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You don't own that accessory.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not save pin.")}
    end
  end

  def handle_event("remove_pin", %{"keypoint" => kp}, socket) do
    scope = socket.assigns.current_scope

    case Drips.remove_pin(scope, socket.assigns.drip, kp) do
      {:ok, _} ->
        {:noreply, assign(socket, :drip, reload(scope, socket.assigns.drip.id))}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove pin.")}
    end
  end

  defp reload(scope, drip_id), do: Drips.get_drip(scope, drip_id)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <header class="flex items-center justify-between mb-6">
        <div class="min-w-0">
          <p class="text-xs opacity-70">
            <.link navigate={~p"/drips"} class="link">Drips</.link> /
          </p>
          <h1 class="text-2xl font-bold truncate">{@drip.name}</h1>
          <p class="text-sm opacity-70">{length(@drip.pins)} pins</p>
        </div>
      </header>

      <section class="border border-base-300 rounded-box p-4 bg-base-200 mb-6">
        <h2 class="font-semibold mb-2">Rename</h2>
        <.form
          for={@rename_form}
          phx-submit="rename"
          class="grid gap-2 sm:grid-cols-[1fr_auto]"
        >
          <input
            type="text"
            name="drip[name]"
            value={@rename_form[:name].value}
            class="input input-bordered"
            required
          />
          <.button class="btn btn-primary">Save name</.button>
        </.form>
      </section>

      <section class="border border-base-300 rounded-box p-4 bg-base-200 mb-6">
        <h2 class="font-semibold mb-3">Pins</h2>

        <%= if @drip.pins == [] do %>
          <p class="text-sm opacity-60 mb-3">No pins yet — add some below.</p>
        <% else %>
          <ul class="grid gap-2 grid-cols-1 sm:grid-cols-2 mb-4">
            <li
              :for={pin <- @drip.pins}
              class="flex items-center gap-3 border border-base-300 rounded p-2 bg-base-100"
            >
              <img
                src={Accessories.image_url(pin.accessory)}
                alt={pin.accessory.name}
                class="size-12 rounded object-contain bg-black/10"
              />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-semibold truncate">{pin.accessory.name}</p>
                <p class="text-xs opacity-70">→ {pin.keypoint}</p>
              </div>
              <button
                phx-click="remove_pin"
                phx-value-keypoint={pin.keypoint}
                data-confirm={"Remove " <> pin.accessory.name <> " from " <> pin.keypoint <> "?"}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-x-mark-micro" class="size-4" />
              </button>
            </li>
          </ul>
        <% end %>

        <%= if @accessories == [] do %>
          <p class="text-sm opacity-70">
            Upload some accessories at <.link navigate={~p"/accessories"} class="link">/accessories</.link>
            before adding pins.
          </p>
        <% else %>
          <.form
            for={@add_form}
            phx-submit="add_pin"
            class="grid gap-2 sm:grid-cols-[2fr_1fr_auto] items-end"
          >
            <label class="form-control">
              <div class="label py-1"><span class="label-text text-xs">Accessory</span></div>
              <select name="pin[accessory_id]" class="select select-bordered select-sm">
                <option :for={a <- @accessories} value={a.id}>{a.name}</option>
              </select>
            </label>
            <label class="form-control">
              <div class="label py-1"><span class="label-text text-xs">Keypoint</span></div>
              <select name="pin[keypoint]" class="select select-bordered select-sm">
                <option :for={kp <- @keypoints} value={kp}>{kp}</option>
              </select>
            </label>
            <.button class="btn btn-primary btn-sm">Add / replace pin</.button>
          </.form>
          <p class="text-xs opacity-60 mt-2">
            Each keypoint can hold one accessory — adding to an existing slot replaces it.
          </p>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
