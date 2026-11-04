defmodule Ledger.OutboxDispatchTest do
  use Ledger.DataCase, async: true

  alias Ledger.{Accounts, Outbox, Transfers}
  alias Ledger.Outbox.Event

  defmodule OkPublisher do
    @behaviour Ledger.Outbox.Publisher
    @impl true
    def publish(topic, payload, id) do
      send(self(), {:published, topic, payload, id})
      :ok
    end
  end

  defmodule DownPublisher do
    @behaviour Ledger.Outbox.Publisher
    @impl true
    def publish(_topic, _payload, _id), do: {:error, :broker_unavailable}
  end

  setup do
    {:ok, acc} = Accounts.open_account(%{owner_name: "Fulano", document: "20000000001"})
    {:ok, tx} = Transfers.deposit(acc.id, 500, "seed")
    %{tx: tx}
  end

  test "publica pendentes, marca como publicados e não republica", %{tx: tx} do
    assert %{published: 1, failed: 0} = Outbox.dispatch(OkPublisher)
    assert_received {:published, "deposit.completed", %{"transaction_id" => id}, event_id}
    assert id == tx.id
    assert %Event{published_at: %DateTime{}} = Repo.get!(Event, event_id)

    assert Outbox.pending_count() == 0
    assert %{published: 0, failed: 0} = Outbox.dispatch(OkPublisher)
  end

  test "falha no broker mantém o evento pendente e registra a tentativa" do
    assert %{published: 0, failed: 1} = Outbox.dispatch(DownPublisher)

    assert [%Event{attempts: 1, last_error: ":broker_unavailable", published_at: nil}] =
             Repo.all(Event)

    assert %{published: 1} = Outbox.dispatch(OkPublisher)
  end
end
