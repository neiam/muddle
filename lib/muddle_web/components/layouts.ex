defmodule MuddleWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MuddleWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  attr :wide, :boolean,
    default: false,
    doc: "when true the inner block fills the full viewport — used by the call view"

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300 bg-base-200">
      <div class="flex-1">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-2">
          <span class="font-mono font-bold tracking-[0.16em] text-accent">MUDDLE</span>
        </.link>
      </div>
      <div class="flex-none">
        <ul class="flex flex-row items-center gap-1">
          <%= if @current_scope && @current_scope.user && @current_scope.user.kind == "registered" do %>
            <li>
              <.link navigate={~p"/rooms"} class="btn btn-ghost btn-sm">
                <.icon name="hero-video-camera-micro" class="size-4" />
                <span class="hidden sm:inline">Rooms</span>
              </.link>
            </li>
            <li>
              <.link navigate={~p"/accessories"} class="btn btn-ghost btn-sm">
                <.icon name="hero-sparkles-micro" class="size-4" />
                <span class="hidden sm:inline">Accessories</span>
              </.link>
            </li>
            <li>
              <.link navigate={~p"/drips"} class="btn btn-ghost btn-sm">
                <.icon name="hero-squares-2x2-micro" class="size-4" />
                <span class="hidden sm:inline">Drips</span>
              </.link>
            </li>
            <li>
              <.link navigate={~p"/users/invites"} class="btn btn-ghost btn-sm">
                <.icon name="hero-envelope-micro" class="size-4" />
                <span class="hidden sm:inline">Invites</span>
              </.link>
            </li>
            <li><span class="divider divider-horizontal mx-0" /></li>
            <li>
              <.theme_toggle />
            </li>
            <li>
              <details class="dropdown dropdown-end">
                <summary class="btn btn-ghost btn-sm">
                  <.icon name="hero-user-circle-micro" class="size-4" />
                  <span class="hidden sm:inline truncate max-w-[12ch]">
                    {user_label(@current_scope.user)}
                  </span>
                </summary>
                <ul class="dropdown-content menu bg-base-200 border border-base-300 rounded-box z-10 mt-1 w-48 p-1 shadow-lg">
                  <li class="menu-title font-mono text-xs truncate">
                    {@current_scope.user.email || "Guest"}
                  </li>
                  <li>
                    <.link navigate={~p"/users/settings"}>
                      <.icon name="hero-cog-6-tooth-micro" class="size-4" /> Settings
                    </.link>
                  </li>
                  <li>
                    <.link href={~p"/users/log-out"} method="delete">
                      <.icon name="hero-arrow-right-on-rectangle-micro" class="size-4" /> Log out
                    </.link>
                  </li>
                </ul>
              </details>
            </li>
          <% else %>
            <li>
              <.theme_toggle />
            </li>
            <%= if @current_scope && @current_scope.user do %>
              <li class="text-xs opacity-70 px-2">
                guest:&nbsp;{user_label(@current_scope.user)}
              </li>
              <li>
                <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
                  Leave
                </.link>
              </li>
            <% else %>
              <li>
                <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">Log in</.link>
              </li>
              <li>
                <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">Register</.link>
              </li>
            <% end %>
          <% end %>
        </ul>
      </div>
    </header>

    <%= if @wide do %>
      <main class="w-full">
        {render_slot(@inner_block)}
      </main>
    <% else %>
      <main class="px-4 py-12 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-3xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  defp user_label(%{display_name: name}) when is_binary(name) and name != "", do: name

  defp user_label(%{email: email}) when is_binary(email),
    do: hd(String.split(email, "@"))

  defp user_label(_), do: "Account"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
