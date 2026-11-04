defmodule Ledger.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Ledger.Repo,
      {DNSCluster, query: Application.get_env(:ledger, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ledger.PubSub}
      # Start a worker by calling: Ledger.Worker.start_link(arg)
      # {Ledger.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Ledger.Supervisor)
  end
end
