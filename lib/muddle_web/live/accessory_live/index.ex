defmodule MuddleWeb.AccessoryLive.Index do
  use MuddleWeb, :live_view

  alias Muddle.Accessories

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Accessories")
     |> assign(:keypoints, Accessories.keypoints())
     |> assign(:form, to_form(%{"name" => "", "default_keypoint" => "head"}, as: "accessory"))
     |> allow_upload(:image,
       accept: ~w(.png .jpg .jpeg .webp .gif .svg),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> stream(:accessories, Accessories.list_accessories(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("validate", _, socket), do: {:noreply, socket}

  def handle_event("save", %{"accessory" => attrs}, socket) do
    %{user: %{id: owner_id}} = scope = socket.assigns.current_scope

    # Move the temp upload into accessory storage *inside* the consume
    # callback — Phoenix LiveView reaps the temp file as soon as the
    # callback returns, so any later File.cp would hit ENOENT.
    stored =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        case Accessories.store_upload(
               path,
               %{filename: entry.client_name, content_type: entry.client_type},
               owner_id
             ) do
          {:ok, info} -> {:ok, info}
          {:error, reason} -> {:postpone, {:error, reason}}
        end
      end)

    case stored do
      [%{} = info] ->
        attrs =
          attrs
          |> Map.put("image_path", info.relative_path)
          |> Map.put("content_type", info.content_type)
          |> Map.put_new("default_keypoint", "head")

        case Accessories.create_accessory(scope, attrs) do
          {:ok, accessory} ->
            {:noreply,
             socket
             |> put_flash(:info, "Uploaded #{accessory.name}.")
             |> stream_insert(:accessories, accessory, at: 0)}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, :form, to_form(cs, as: "accessory"))}
        end

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Upload failed: #{inspect(reason)}")}

      [] ->
        {:noreply, put_flash(socket, :error, "Pick an image to upload.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    accessory = Accessories.get_accessory(socket.assigns.current_scope, id)

    case accessory && Accessories.delete_accessory(socket.assigns.current_scope, accessory) do
      {:ok, deleted} -> {:noreply, stream_delete(socket, :accessories, deleted)}
      _ -> {:noreply, put_flash(socket, :error, "Could not delete.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <header class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold">Accessories</h1>
          <p class="text-sm opacity-70">Upload images to pin onto people during calls.</p>
        </div>
      </header>

      <.form
        for={@form}
        phx-submit="save"
        phx-change="validate"
        class="border border-base-300 rounded-box p-4 mb-6 bg-base-200 grid gap-3"
      >
        <.input field={@form[:name]} placeholder="Wizard hat" required />
        <label class="form-control">
          <div class="label"><span class="label-text">Default keypoint</span></div>
          <select name="accessory[default_keypoint]" class="select select-bordered">
            <option :for={kp <- @keypoints} value={kp}>{kp}</option>
          </select>
        </label>

        <div class="border border-dashed border-base-300 rounded p-4">
          <.live_file_input upload={@uploads.image} class="file-input file-input-bordered w-full" />
          <p :for={err <- upload_errors(@uploads.image)} class="text-error text-xs mt-1">
            {humanize_upload_error(err)}
          </p>
          <ul class="mt-2">
            <li :for={entry <- @uploads.image.entries} class="flex items-center gap-2 text-xs">
              <span class="truncate flex-1">{entry.client_name}</span>
              <span>{entry.progress}%</span>
            </li>
          </ul>
        </div>

        <.button class="btn btn-primary">Upload accessory</.button>
      </.form>

      <ul id="accessories" phx-update="stream" class="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <li
          id="accessories-empty"
          class="hidden only:block col-span-full text-center text-sm opacity-60 py-8"
        >
          No accessories yet.
        </li>
        <li
          :for={{dom_id, a} <- @streams.accessories}
          id={dom_id}
          class="border border-base-300 rounded-box p-3 bg-base-200"
        >
          <img src={Accessories.image_url(a)} alt={a.name} class="w-full h-32 object-contain mb-2" />
          <p class="font-semibold truncate">{a.name}</p>
          <p :if={a.default_keypoint} class="text-xs opacity-70">→ {a.default_keypoint}</p>
          <button
            phx-click="delete"
            phx-value-id={a.id}
            data-confirm="Delete this accessory?"
            class="btn btn-ghost btn-xs text-error mt-2"
          >
            <.icon name="hero-trash-micro" class="size-4" /> Remove
          </button>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  defp humanize_upload_error(:too_large), do: "Image is too large (max 5MB)."
  defp humanize_upload_error(:not_accepted), do: "File type not accepted."
  defp humanize_upload_error(:too_many_files), do: "Only one image at a time."
  defp humanize_upload_error(other), do: to_string(other)
end
