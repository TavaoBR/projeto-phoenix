defmodule LedgerEvents do
  @moduledoc """
  Integração do ledger com o RabbitMQ.

  Topologia:

      ledger.events (exchange topic, durável)
        └── routing key = tópico do evento (`transfer.completed`, `deposit.completed`)
              └── ledger.notifications (fila durável, binding `*.completed`)
                    └── dead letter → ledger.events.dlx → ledger.notifications.dlq

  * `LedgerEvents.AMQPPublisher` publica com *publisher confirms* e mensagens persistentes;
  * `LedgerEvents.OutboxRelay` lê o outbox periodicamente e publica via publisher;
  * `LedgerEvents.NotificationPipeline` (Broadway) consome a fila e grava notificações.
  """

  @exchange "ledger.events"
  @dead_letter_exchange "ledger.events.dlx"
  @notifications_queue "ledger.notifications"

  def exchange, do: @exchange
  def dead_letter_exchange, do: @dead_letter_exchange
  def notifications_queue, do: @notifications_queue
  def dead_letter_queue, do: @notifications_queue <> ".dlq"

  @doc false
  def config(key, default \\ nil) do
    Application.get_env(:ledger_events, key, default)
  end

  @doc "Declara exchanges, filas e bindings (idempotente)."
  @spec declare_topology(AMQP.Channel.t()) :: :ok
  def declare_topology(chan) do
    :ok = AMQP.Exchange.declare(chan, @exchange, :topic, durable: true)
    :ok = AMQP.Exchange.declare(chan, @dead_letter_exchange, :fanout, durable: true)

    {:ok, _} = AMQP.Queue.declare(chan, dead_letter_queue(), durable: true)
    :ok = AMQP.Queue.bind(chan, dead_letter_queue(), @dead_letter_exchange)

    {:ok, _} =
      AMQP.Queue.declare(chan, @notifications_queue,
        durable: true,
        arguments: [{"x-dead-letter-exchange", :longstr, @dead_letter_exchange}]
      )

    :ok = AMQP.Queue.bind(chan, @notifications_queue, @exchange, routing_key: "*.completed")
  end
end
