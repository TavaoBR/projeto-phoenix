defmodule LedgerWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  @prometheus :ledger_prometheus

  @doc "Métricas no formato texto do Prometheus."
  def scrape, do: TelemetryMetricsPrometheus.Core.scrape(@prometheus)

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      # Agrega as métricas em memória; o GET /metrics (LedgerWeb.MetricsController) as expõe.
      {TelemetryMetricsPrometheus.Core, metrics: prometheus_metrics(), name: @prometheus}
    ]

    Supervisor.init(children ++ datadog_reporter(), strategy: :one_for_one)
  end

  # Envia as mesmas métricas ao Datadog Agent via DogStatsD (UDP, formato com tags).
  # Só liga quando DD_AGENT_HOST está definido (ver config/runtime.exs). As tags
  # `service`/`env` são aplicadas pelo próprio agent (DD_TAGS no docker-compose).
  defp datadog_reporter do
    case Application.get_env(:ledger_web, :datadog) do
      nil ->
        []

      opts ->
        [
          {TelemetryMetricsStatsd,
           metrics: metrics(),
           host: Keyword.fetch!(opts, :host),
           port: Keyword.get(opts, :port, 8125),
           formatter: :datadog}
        ]
    end
  end

  # O formato Prometheus não suporta `summary`; usamos as distribuições no lugar.
  defp prometheus_metrics do
    Enum.reject(metrics(), &match?(%Telemetry.Metrics.Summary{}, &1))
  end

  def metrics do
    [
      # Métricas de negócio (emitidas por Ledger.Transfers via :telemetry.span)
      distribution("ledger.transaction.stop.duration",
        tags: [:type, :result],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250, 500, 1000]],
        description: "Duração e volume (_count) de movimentações por tipo e resultado"
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route, :status],
        tag_values: &Map.put(&1, :status, &1.conn.status),
        unit: {:native, :millisecond},
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250, 500, 1000]],
        description: "Latência HTTP por rota"
      ),

      # Mensageria (outbox → RabbitMQ → Broadway)
      sum("ledger.outbox.dispatch.published",
        description: "Eventos do outbox confirmados pelo RabbitMQ"
      ),
      sum("ledger.outbox.dispatch.failed",
        description: "Tentativas de publicação que falharam (evento segue pendente)"
      ),
      last_value("ledger.outbox.pending.count",
        description: "Eventos aguardando publicação (backlog do outbox)"
      ),
      sum("ledger.notifications.consumed.count",
        tags: [:result],
        description: "Mensagens processadas pelo consumidor Broadway"
      ),

      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("ledger.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("ledger.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("ledger.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("ledger.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("ledger.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_outbox_backlog, []}
    ]
  end

  @doc false
  def measure_outbox_backlog do
    :telemetry.execute([:ledger, :outbox, :pending], %{count: Ledger.Outbox.pending_count()}, %{})
  rescue
    # Banco indisponível (ou sandbox de testes): pula esta amostra sem derrubar o poller.
    _ in [DBConnection.ConnectionError, DBConnection.OwnershipError] -> :ok
  end
end
