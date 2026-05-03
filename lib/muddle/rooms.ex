defmodule Muddle.Rooms do
  @moduledoc """
  The Rooms context — owns video-chat rooms, memberships, and guest
  access tokens.

  A room has:
    * an owner (`%User{}`)
    * a slug used in URLs (`/r/:slug`)
    * a roster of memberships (registered users with persistent access)
    * any number of guest links (single-use or shared, optionally
      expiring) which mint anonymous users on redemption
  """

  import Ecto.Query, warn: false

  alias Muddle.Repo
  alias Muddle.Accounts
  alias Muddle.Accounts.{Scope, User}
  alias Muddle.Rooms.{Room, Membership, GuestLink}

  ## Rooms ------------------------------------------------------------------

  def list_rooms_for(%Scope{user: %User{id: user_id}}) do
    from(r in Room,
      left_join: m in Membership,
      on: m.room_id == r.id and m.user_id == ^user_id,
      where: r.owner_id == ^user_id or not is_nil(m.id),
      order_by: [desc: r.inserted_at],
      distinct: r.id
    )
    |> Repo.all()
  end

  def get_room!(id), do: Repo.get!(Room, id)

  def get_room_by_slug(slug) when is_binary(slug),
    do: Repo.get_by(Room, slug: slug)

  def get_room_by_slug!(slug), do: Repo.get_by!(Room, slug: slug)

  def create_room(%Scope{user: %User{id: owner_id}}, attrs) do
    %Room{owner_id: owner_id}
    |> Room.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_room(%Scope{user: %User{id: owner_id}}, %Room{owner_id: owner_id} = room, attrs) do
    room
    |> Room.update_changeset(attrs)
    |> Repo.update()
  end

  def update_room(_scope, _room, _attrs), do: {:error, :forbidden}

  def delete_room(%Scope{user: %User{id: owner_id}}, %Room{owner_id: owner_id} = room),
    do: Repo.delete(room)

  def delete_room(_scope, _room), do: {:error, :forbidden}

  ## Membership -------------------------------------------------------------

  @doc """
  Returns the role the scope's user has in this room (`:owner`,
  `:member`, `:guest`, or `nil` if no access).
  """
  def role(%Scope{user: nil}, _room), do: nil

  def role(%Scope{user: %User{id: user_id}}, %Room{owner_id: user_id}), do: :owner

  def role(%Scope{user: %User{id: user_id, kind: kind}}, %Room{id: room_id}) do
    cond do
      Repo.exists?(from m in Membership, where: m.room_id == ^room_id and m.user_id == ^user_id) ->
        :member

      kind == "anonymous" ->
        :guest

      true ->
        nil
    end
  end

  def can_join?(scope, room), do: not is_nil(role(scope, room))

  def add_member(%Scope{user: %User{id: owner_id}}, %Room{owner_id: owner_id, id: room_id}, %User{
        id: user_id
      }) do
    %Membership{}
    |> Membership.changeset(%{room_id: room_id, user_id: user_id})
    |> Repo.insert(on_conflict: :nothing)
  end

  def add_member(_scope, _room, _user), do: {:error, :forbidden}

  def remove_member(
        %Scope{user: %User{id: owner_id}},
        %Room{owner_id: owner_id, id: room_id},
        %User{
          id: user_id
        }
      ) do
    {n, _} =
      from(m in Membership, where: m.room_id == ^room_id and m.user_id == ^user_id)
      |> Repo.delete_all()

    {:ok, n}
  end

  def remove_member(_, _, _), do: {:error, :forbidden}

  ## Guest links ------------------------------------------------------------

  @doc "Lists every guest link the caller owns, newest first."
  def list_guest_links(%Scope{user: %User{id: owner_id}}, %Room{id: room_id, owner_id: owner_id}) do
    from(g in GuestLink,
      where: g.room_id == ^room_id,
      order_by: [desc: g.inserted_at]
    )
    |> Repo.all()
  end

  def list_guest_links(_, _), do: []

  def create_guest_link(
        %Scope{user: %User{id: owner_id}},
        %Room{id: room_id, owner_id: owner_id},
        attrs \\ %{}
      ) do
    %GuestLink{room_id: room_id, created_by_id: owner_id}
    |> GuestLink.create_changeset(attrs)
    |> Repo.insert()
  end

  def revoke_guest_link(%Scope{user: %User{id: owner_id}}, %GuestLink{} = link) do
    link = Repo.preload(link, :room)

    if link.room.owner_id == owner_id do
      link
      |> Ecto.Changeset.change(revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
    else
      {:error, :forbidden}
    end
  end

  @doc "Looks up a guest link by token; returns `nil` if not active."
  def get_active_guest_link(token) when is_binary(token) do
    case Repo.get_by(GuestLink, token: token) do
      nil -> nil
      link -> if GuestLink.active?(link), do: Repo.preload(link, :room), else: nil
    end
  end

  def get_active_guest_link(_), do: nil

  @doc """
  Redeems a guest link. If the visitor has no current user, mints an
  anonymous one. Either way, returns the room and the (possibly newly
  created) user.
  """
  def redeem_guest_link(token, current_user, attrs \\ %{}) when is_binary(token) do
    case get_active_guest_link(token) do
      nil ->
        {:error, :invalid_link}

      %GuestLink{room: %Room{} = room} ->
        with {:ok, user} <- ensure_user_for_guest(current_user, attrs) do
          {:ok, user, room}
        end
    end
  end

  defp ensure_user_for_guest(%User{} = user, _attrs), do: {:ok, user}
  defp ensure_user_for_guest(nil, attrs), do: Accounts.register_anonymous_user(attrs)
end
