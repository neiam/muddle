defmodule MuddleWeb.GuestLinkController do
  use MuddleWeb, :controller

  alias Muddle.Rooms
  alias MuddleWeb.UserAuth

  @doc """
  Redeems a guest link. If the visitor has no session, they're issued
  an anonymous user and logged in. Either way they end up at `/r/:slug`.
  """
  def show(conn, %{"token" => token} = params) do
    current_user = current_user(conn)
    attrs = %{display_name: params["name"]}

    case Rooms.redeem_guest_link(token, current_user, attrs) do
      {:ok, user, room} ->
        conn = put_session(conn, :user_return_to, ~p"/r/#{room.slug}")
        maybe_log_in(conn, user, current_user)

      {:error, :invalid_link} ->
        conn
        |> put_flash(:error, "That guest link is invalid, expired, or has been revoked.")
        |> redirect(to: ~p"/")

      {:error, _} ->
        conn
        |> put_flash(:error, "We couldn't redeem that guest link.")
        |> redirect(to: ~p"/")
    end
  end

  defp current_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: user} -> user
      _ -> nil
    end
  end

  # Already-logged-in visitor: just route them to the call.
  defp maybe_log_in(conn, _user, %{} = _existing),
    do: redirect(conn, to: get_session(conn, :user_return_to))

  # Brand-new anonymous user: log them in, which then redirects.
  defp maybe_log_in(conn, user, nil), do: UserAuth.log_in_user(conn, user)
end
