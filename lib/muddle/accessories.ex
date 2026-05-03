defmodule Muddle.Accessories do
  @moduledoc """
  The Accessories context — image overlays (hats, glasses, etc.) that a
  user can pin to a body keypoint during a video call.

  An accessory is owned by a user and lives at a path on disk under
  `:muddle, :accessory_storage`. Pinning is handled live by
  `Muddle.Rooms.Authority`; the `Pin` schema here is for persistent
  defaults (auto-pin when joining a call).
  """

  import Ecto.Query, warn: false

  alias Muddle.Repo
  alias Muddle.Accounts.{Scope, User}
  alias Muddle.Accessories.{Accessory, Pin}

  @keypoints ~w(
    head
    forehead
    left_eye
    right_eye
    nose
    mouth
    left_ear
    right_ear
    chin
    neck
    left_shoulder
    right_shoulder
    chest
    left_hand
    right_hand
  )

  @doc "List of valid keypoint identifiers an accessory may be pinned to."
  def keypoints, do: @keypoints

  ## Accessories ------------------------------------------------------------

  def list_accessories(%Scope{user: %User{id: user_id}}) do
    from(a in Accessory,
      where: a.owner_id == ^user_id and is_nil(a.deleted_at),
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  def list_accessories(_), do: []

  def get_accessory!(id), do: Repo.get!(Accessory, id)

  def get_accessory(%Scope{user: %User{id: user_id}}, id) do
    Repo.get_by(Accessory, id: id, owner_id: user_id)
  end

  def get_accessory(_, _), do: nil

  @doc """
  Creates a new accessory. The caller is expected to have already
  copied the uploaded file into accessory storage via `store_upload/3`
  (typically inside a `consume_uploaded_entries` callback, since
  Phoenix LiveView reaps the temp file as soon as that callback
  returns). The resulting `:image_path` and `:content_type` are passed
  in via `attrs`.
  """
  def create_accessory(%Scope{user: %User{id: owner_id}}, attrs) do
    %Accessory{owner_id: owner_id}
    |> Accessory.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Copies the file at `src_path` into accessory storage for `owner_id`,
  returning `{:ok, %{relative_path:, content_type:}}` so the caller can
  pass those into `create_accessory/2`. Validates the extension up
  front so we don't move junk into storage.

  Call this *inside* `Phoenix.LiveView.consume_uploaded_entries/3` —
  the LV reaps the temp file as soon as the callback returns.
  """
  @spec store_upload(Path.t(), %{filename: String.t(), content_type: String.t() | nil}, integer()) ::
          {:ok, %{relative_path: String.t(), content_type: String.t()}} | {:error, term()}
  def store_upload(src_path, %{filename: filename} = entry, owner_id)
      when is_binary(src_path) and is_integer(owner_id) do
    ext = filename |> Path.extname() |> String.downcase()

    cond do
      ext not in ~w(.png .jpg .jpeg .webp .gif .svg) ->
        {:error, :unsupported_format}

      not File.exists?(src_path) ->
        {:error, {:fs, :enoent}}

      true ->
        rel =
          Path.join([
            "u#{owner_id}",
            "#{:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)}#{ext}"
          ])

        dst = Path.join(storage_root(), rel)
        File.mkdir_p!(Path.dirname(dst))

        case File.cp(src_path, dst) do
          :ok ->
            {:ok,
             %{
               relative_path: rel,
               content_type: Map.get(entry, :content_type) || guess_content_type(filename)
             }}

          {:error, reason} ->
            {:error, {:fs, reason}}
        end
    end
  end

  def update_accessory(
        %Scope{user: %User{id: owner_id}},
        %Accessory{owner_id: owner_id} = accessory,
        attrs
      ) do
    accessory
    |> Accessory.update_changeset(attrs)
    |> Repo.update()
  end

  def update_accessory(_, _, _), do: {:error, :forbidden}

  @doc """
  Updates only the calibration fields (`default_scale`,
  `default_offset_x`, `default_offset_y`). Used by the in-call
  drag/scale gestures.
  """
  def update_calibration(
        %Scope{user: %User{id: owner_id}},
        %Accessory{owner_id: owner_id} = accessory,
        attrs
      ) do
    accessory
    |> Accessory.calibration_changeset(attrs)
    |> Repo.update()
  end

  def update_calibration(_, _, _), do: {:error, :forbidden}

  @doc """
  Soft-deletes an accessory. We keep the row so any historical pin
  references still resolve.
  """
  def delete_accessory(
        %Scope{user: %User{id: owner_id}},
        %Accessory{owner_id: owner_id} = accessory
      ) do
    accessory
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def delete_accessory(_, _), do: {:error, :forbidden}

  @doc """
  Returns the absolute on-disk URL prefix for an accessory's image,
  suitable for use in an `<img src=>`.
  """
  def image_url(%Accessory{image_path: rel}) do
    Path.join(url_prefix(), rel)
  end

  ## Default pins -----------------------------------------------------------

  def list_default_pins(%Scope{user: %User{id: user_id}}) do
    from(p in Pin,
      where: p.user_id == ^user_id,
      preload: :accessory
    )
    |> Repo.all()
  end

  def upsert_default_pin(
        %Scope{user: %User{id: user_id}},
        %Accessory{owner_id: user_id, id: aid},
        keypoint,
        transform \\ %{}
      )
      when keypoint in @keypoints do
    %Pin{}
    |> Pin.changeset(%{
      user_id: user_id,
      accessory_id: aid,
      keypoint: keypoint,
      transform: transform
    })
    |> Repo.insert(
      on_conflict: [set: [accessory_id: aid, transform: transform]],
      conflict_target: [:user_id, :keypoint]
    )
  end

  def remove_default_pin(%Scope{user: %User{id: user_id}}, keypoint)
      when keypoint in @keypoints do
    {n, _} =
      from(p in Pin, where: p.user_id == ^user_id and p.keypoint == ^keypoint)
      |> Repo.delete_all()

    {:ok, n}
  end

  ## Internal: file storage -------------------------------------------------

  defp guess_content_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".webp" -> "image/webp"
      ".gif" -> "image/gif"
      ".svg" -> "image/svg+xml"
      _ -> "application/octet-stream"
    end
  end

  defp storage_root,
    do: Application.fetch_env!(:muddle, :accessory_storage)[:root]

  defp url_prefix,
    do: Application.fetch_env!(:muddle, :accessory_storage)[:url_prefix]
end
