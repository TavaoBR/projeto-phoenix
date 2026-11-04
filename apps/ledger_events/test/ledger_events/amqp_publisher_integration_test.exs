defmodule LedgerEvents.AMQPPublisherIntegrationTest do
  use LedgerEvents.EventsCase, async: false

  @moduletag :rabbitmq

  alias LedgerEvents.{AMQPPublisher, OutboxRelay}

  setup do
    url = System.fetch_env!("RABBITMQ_URL")
    {:ok, conn} = AMQP.Connection.open(url)
    {:ok, chan} = AMQP.Channel.open(conn)
    :ok = LedgerEvents.declare_topology(chan)
    {:ok, _} = AMQP.Queue.purge(chan, LedgerEvents.notifications_queue())
    on_exit(fn -> AMQP.Connection.close(conn) end)

    start_supervised!({AMQPPublisher, url: url})
    wait_connected()
    %{chan: chan}
  end

  defp wait_connected(tries \\ 50) do
    case AMQPPublisher.publish("probe.ignored", %{}, "probe") do
      :ok -> :ok
      _ when tries > 0 -> Process.sleep(100) && wait_connected(tries - 1)
    end
  end

  test "outbox → relay → RabbitMQ entrega mensagem persistente e roteada", %{chan: chan} do
    {:ok, tx} = Ledger.Transfers.deposit(account!().id, 4_200, "int-1")
    start_supervised!({OutboxRelay, publisher: AMQPPublisher, interval: 10})

    {body, meta} = get_message(chan)
    assert meta.routing_key == "deposit.completed"
    assert meta.persistent
    assert meta.content_type == "application/json"
    assert %{"transaction_id" => id, "amount_cents" => 4_200} = Jason.decode!(body)
    assert id == tx.id
    assert Ledger.Outbox.pending_count() == 0
  end

  test "reconecta sozinho quando a conexão com o broker cai" do
    %{conn: conn} = :sys.get_state(AMQPPublisher)
    Process.exit(conn.pid, :kill)

    # Enquanto reconecta, o evento fica pendente em vez de ser perdido.
    assert {:error, _} = AMQPPublisher.publish("x.completed", %{}, "during")
    assert Process.alive?(Process.whereis(AMQPPublisher))

    Process.sleep(2_200)
    wait_connected()
    assert %{conn: %AMQP.Connection{pid: new_pid}} = :sys.get_state(AMQPPublisher)
    refute new_pid == conn.pid
  end

  defp get_message(chan, tries \\ 50) do
    case AMQP.Basic.get(chan, LedgerEvents.notifications_queue(), no_ack: true) do
      {:ok, body, meta} -> {body, meta}
      {:empty, _} when tries > 0 -> Process.sleep(50) && get_message(chan, tries - 1)
    end
  end
end
