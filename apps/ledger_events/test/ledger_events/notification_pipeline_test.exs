defmodule LedgerEvents.NotificationPipelineTest do
  use LedgerEvents.EventsCase, async: false

  alias Ledger.Outbox.Event
  alias LedgerEvents.NotificationPipeline

  setup do
    start_supervised!(
      {NotificationPipeline, producer: {Broadway.DummyProducer, []}, concurrency: 1}
    )

    :ok
  end

  defp event_json(tx),
    do: tx |> Event.from_transaction() |> Map.get(:payload) |> Jason.encode!()

  test "consome evento e grava notificações" do
    from = account!()
    to = account!()
    {:ok, _} = Ledger.Transfers.deposit(from.id, 1_000, "p-d")
    {:ok, tx} = Ledger.Transfers.transfer(from.id, to.id, 400, "p-t")

    ref = Broadway.test_message(NotificationPipeline, event_json(tx))
    assert_receive {:ack, ^ref, [_ok], []}, 1_000

    assert [%{kind: :credit, amount_cents: 400}] = Ledger.Notifications.list_for_account(to.id)
  end

  test "mensagem duplicada é confirmada sem duplicar notificação" do
    acc = account!()
    {:ok, tx} = Ledger.Transfers.deposit(acc.id, 700, "p-dup")

    ref = Broadway.test_batch(NotificationPipeline, [event_json(tx), event_json(tx)])
    assert_receive {:ack, ^ref, [_, _], []}, 1_000
    assert [_one] = Ledger.Notifications.list_for_account(acc.id)
  end

  test "mensagem inválida falha (vai para a DLQ no RabbitMQ)" do
    ref = Broadway.test_message(NotificationPipeline, "{nao-e-json")
    assert_receive {:ack, ^ref, [], [failed]}, 1_000
    assert {:failed, %Jason.DecodeError{}} = failed.status

    ref = Broadway.test_message(NotificationPipeline, ~s({"type":"x"}))
    assert_receive {:ack, ^ref, [], [%{status: {:failed, :invalid_event}}]}, 1_000
  end
end
