defmodule LedgerEvents.NotificationPipeline do
  @moduledoc """
  Consumidor Broadway da fila `ledger.notifications`.

  * concorrência controlada (`prefetch_count` + processors);
  * ack manual: a mensagem só sai da fila depois de gravada no banco;
  * mensagem inválida ou erro de processamento → `reject` sem requeue, e o
    RabbitMQ a manda para a dead letter queue `ledger.notifications.dlq`;
  * reprocessamento é seguro porque `Ledger.Notifications.record_event/1` é idempotente.

  O producer é injetável (`:producer`) para os testes usarem `Broadway.DummyProducer`.
  """
  use Broadway

  require Logger

  alias Broadway.Message

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: Keyword.get_lazy(opts, :producer, fn -> rabbit_producer(opts) end)],
      processors: [default: [concurrency: Keyword.get(opts, :concurrency, 4)]]
    )
  end

  defp rabbit_producer(opts) do
    options = [
      queue: LedgerEvents.notifications_queue(),
      connection: Keyword.fetch!(opts, :url),
      # Garante a topologia mesmo se o consumidor subir antes do publisher.
      after_connect: &LedgerEvents.declare_topology/1,
      qos: [prefetch_count: 20],
      on_failure: :reject,
      metadata: [:message_id, :routing_key]
    ]

    {BroadwayRabbitMQ.Producer, options}
  end

  @impl true
  def handle_message(_processor, %Message{} = message, _context) do
    with {:ok, event} <- Jason.decode(message.data),
         {:ok, _count} <- Ledger.Notifications.record_event(event) do
      :telemetry.execute([:ledger, :notifications, :consumed], %{count: 1}, %{result: :ok})
      message
    else
      {:error, reason} ->
        Logger.error("Mensagem rejeitada para a DLQ: #{inspect(reason)}")
        :telemetry.execute([:ledger, :notifications, :consumed], %{count: 1}, %{result: :error})
        Message.failed(message, reason)
    end
  end
end
