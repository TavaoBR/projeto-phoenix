defmodule LedgerWeb.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Encaminha crashes/erros logados para o Sentry.
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{})

    children = [
      LedgerWeb.Telemetry,
      # Start a worker by calling: LedgerWeb.Worker.start_link(arg)
      # {LedgerWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      LedgerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LedgerWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LedgerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
