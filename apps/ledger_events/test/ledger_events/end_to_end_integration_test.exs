defmodule LedgerEvents.EndToEndIntegrationTest do
  use LedgerEvents.EventsCase, async: false

  @moduletag :rabbitmq

  alias LedgerEvents.{AMQPPublisher, NotificationPipeline, OutboxRelay}

  setup do
    url = System.fetch_env!("RABBITMQ_URL")
    {:ok, conn} = AMQP.Connection.open(url)
    {:ok, chan} = AMQP.Channel.open(conn)
    :ok = LedgerEvents.declare_topology(chan)
    {:ok, _} = AMQP.Queue.purge(chan, LedgerEvents.notifications_queue())
    {:ok, _} = AMQP.Queue.purge(chan, LedgerEvents.dead_letter_queue())
    on_exit(fn -> AMQP.Connection.close(conn) end)

    start_supervised!({AMQPPublisher, url: url})
    start_supervised!({OutboxRelay, publisher: AMQPPublisher, interval: 20})
    start_supervised!({NotificationPipeline, url: url, concurrency: 2})
    %{chan: chan}
  end

  defp eventually(fun, tries \\ 100) do
    case fun.() do
      falsy when falsy in [nil, false, []] and tries > 0 ->
        Process.sleep(50)
        eventually(fun, tries - 1)

      result ->
        result
    end
  end

  test "transferência confirmada vira notificação via RabbitMQ + Broadway" do
    from = account!("Ana")
    to = account!("Bruno")
    {:ok, _} = Ledger.Transfers.deposit(from.id, 5_000, "e2e-d")
    {:ok, _} = Ledger.Transfers.transfer(from.id, to.id, 1_999, "e2e-t")

    assert [%{kind: :credit, message: "Transferência de R$ 19,99 recebida"}] =
             eventually(fn -> Ledger.Notifications.list_for_account(to.id) end)

    assert [_debit, _deposit] =
             eventually(fn ->
               match?([_, _], Ledger.Notifications.list_for_account(from.id)) &&
                 Ledger.Notifications.list_for_account(from.id)
             end)

    assert eventually(fn -> Ledger.Outbox.pending_count() == 0 end)
  end

  test "mensagem inválida é rejeitada e cai na dead letter queue", %{chan: chan} do
    :ok = AMQP.Basic.publish(chan, LedgerEvents.exchange(), "transfer.completed", "lixo")

    assert {:ok, "lixo", _meta} =
             eventually(fn ->
               case AMQP.Basic.get(chan, LedgerEvents.dead_letter_queue(), no_ack: true) do
                 {:ok, _, _} = hit -> hit
                 {:empty, _} -> nil
               end
             end)
  end
end
