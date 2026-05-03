defmodule MuddleWeb.Router do
  use MuddleWeb, :router

  import MuddleWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MuddleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MuddleWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/g/:token", GuestLinkController, :show
  end

  # Authenticated routes (must be a registered user) -----------------------
  scope "/", MuddleWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{MuddleWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/users/invites", UserLive.Invites, :index

      live "/rooms", RoomLive.Index, :index
      live "/rooms/new", RoomLive.Index, :new
      live "/rooms/:slug/manage", RoomLive.Manage, :show

      live "/accessories", AccessoryLive.Index, :index
      live "/accessories/new", AccessoryLive.Index, :new

      live "/drips", DripLive.Index, :index
      live "/drips/:id/edit", DripLive.Edit, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # Pages accessible to anyone with a current scope (registered or guest) --
  scope "/", MuddleWeb do
    pipe_through :browser

    live_session :current_user,
      on_mount: [{MuddleWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new

      # Anyone with a session (incl. anonymous guests) can be in a call.
      live "/r/:slug", RoomLive.Call, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:muddle, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MuddleWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
