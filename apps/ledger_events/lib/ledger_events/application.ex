defmodule LedgerEvents.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: LedgerEvents.Supervisor)
  end

  # Nos testes os workers ficam desligados (`config :ledger_events, relay: false`)
  # e cada teste sobe só o que precisa, sem depender de um broker real.
  defp children do
    url = LedgerEvents.config(:amqp_url)
    relay(url) ++ consumer(url)
  end

  defp relay(url) do
    if LedgerEvents.config(:relay, true) do
      [
        {LedgerEvents.AMQPPublisher, url: url},
        {LedgerEvents.OutboxRelay,
         publisher: LedgerEvents.AMQPPublisher,
         interval: LedgerEvents.config(:relay_interval_ms, 1_000)}
      ]
    else
      []
    end
  end

  defp consumer(url) do
    if LedgerEvents.config(:consumer, true),
      do: [{LedgerEvents.NotificationPipeline, url: url}],
      else: []
  end
end
