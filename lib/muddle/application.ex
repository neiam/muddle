defmodule Muddle.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    topologies = Application.get_env(:libcluster, :topologies, [])

    children =
      [
        MuddleWeb.Telemetry,
        Muddle.Repo,
        {DNSCluster, query: Application.get_env(:muddle, :dns_cluster_query) || :ignore}
      ] ++
        cluster_children(topologies) ++
        [
          {Phoenix.PubSub, name: Muddle.PubSub},
          Muddle.Rooms.Authority,
          Muddle.Media.RoomEngine,
          MuddleWeb.Presence,
          MuddleWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: Muddle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MuddleWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp cluster_children([]), do: []

  defp cluster_children(topologies) do
    [{Cluster.Supervisor, [topologies, [name: Muddle.ClusterSupervisor]]}]
  end
end
