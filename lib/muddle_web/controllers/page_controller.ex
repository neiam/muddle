defmodule MuddleWeb.PageController do
  use MuddleWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
