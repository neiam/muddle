defmodule MuddleWeb.Presence do
  @moduledoc """
  Tracks per-room presence: who's in a video call, their connection
  state, and currently-pinned accessories.
  """
  use Phoenix.Presence,
    otp_app: :muddle,
    pubsub_server: Muddle.PubSub
end
