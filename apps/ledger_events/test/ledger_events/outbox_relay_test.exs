defmodule LedgerEvents.OutboxRelayTest do
  use LedgerEvents.EventsCase, async: false

  alias LedgerEvents.{AMQPPublisher, OutboxRelay}

  defmodule ForwardPublisher do
    @moduledoc false
    @behaviour Ledger.Outbox.Publisher

    @impl true
    def publish(topic, payload, id) do
      send(:persistent_term.get({__MODULE__, :test_pid}), {:published, topic, payload, id})
      :ok
    end
  end

  test "relay drena o outbox e publica cada evento uma única vez" do
    :persistent_term.put({ForwardPublisher, :test_pid}, self())
    {:ok, tx} = Ledger.Transfers.deposit(account!().id, 100, "relay-1")

    start_supervised!({OutboxRelay, publisher: ForwardPublisher, interval: 10})

    assert_receive {:published, "deposit.completed", %{"transaction_id" => id}, _}, 1_000
    assert id == tx.id
    refute_receive {:published, _, _, _}, 100
    assert Ledger.Outbox.pending_count() == 0
  end

  test "publisher sem conexão devolve erro em vez de travar o relay" do
    start_supervised!({AMQPPublisher, url: "amqp://guest:guest@127.0.0.1:1"})
    assert {:error, :not_connected} = AMQPPublisher.publish("x.completed", %{}, "id")
  end

  test "publisher fora do ar devolve erro" do
    assert {:error, {:publisher_unavailable, _}} = AMQPPublisher.publish("x.completed", %{}, "id")
  end
end
