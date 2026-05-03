defmodule Muddle.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  Carries the current user (registered or anonymous guest). Public
  context functions take a `%Scope{}` so they can authorize calls and
  scope pubsub topics.
  """

  alias Muddle.Accounts.User

  defstruct user: nil

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
