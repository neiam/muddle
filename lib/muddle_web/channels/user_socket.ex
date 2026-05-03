defmodule MuddleWeb.UserSocket do
  use Phoenix.Socket

  alias Muddle.Accounts
  alias Muddle.Accounts.Scope

  channel "room:*", MuddleWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case Phoenix.Token.verify(MuddleWeb.Endpoint, "user socket", token, max_age: 86_400) do
      {:ok, user_id} ->
        case Accounts.get_user!(user_id) do
          nil -> :error
          user -> {:ok, assign(socket, :scope, Scope.for_user(user))}
        end

      _ ->
        :error
    end
  rescue
    Ecto.NoResultsError -> :error
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket) do
    case socket.assigns[:scope] do
      %Scope{user: %{id: id}} -> "users_socket:#{id}"
      _ -> nil
    end
  end
end
