defmodule Ledger.OutboxTest do
  use Ledger.DataCase, async: true

  alias Ledger.{Accounts, Transfers}
  alias Ledger.Outbox.Event

  defp account!(doc) do
    {:ok, acc} = Accounts.open_account(%{owner_name: "Fulano", document: doc})
    acc
  end

  defp events, do: Repo.all(from e in Event, order_by: e.inserted_at)

  setup do
    from = account!("10000000001")
    to = account!("10000000002")
    {:ok, _} = Transfers.deposit(from.id, 1_000, "seed")
    %{from: from, to: to}
  end

  test "depósito grava deposit.completed na mesma transação", %{from: from} do
    assert [%Event{topic: "deposit.completed", payload: payload, published_at: nil}] = events()
    assert payload["to_account_id"] == from.id
    assert payload["amount_cents"] == 1_000
  end

  test "transferência confirmada grava transfer.completed", %{from: from, to: to} do
    {:ok, tx} = Transfers.transfer(from.id, to.id, 300, "t-1")

    assert %Event{payload: payload} = Enum.find(events(), &(&1.topic == "transfer.completed"))
    assert payload["transaction_id"] == tx.id
    assert payload["from_account_id"] == from.id
    assert payload["to_account_id"] == to.id
    assert payload["amount_cents"] == 300
  end

  test "transferência recusada não gera evento", %{from: from, to: to} do
    {:error, :insufficient_funds} = Transfers.transfer(from.id, to.id, 5_000, "t-2")
    assert length(events()) == 1
  end

  test "retentativa idempotente não duplica o evento", %{from: from, to: to} do
    {:ok, _} = Transfers.transfer(from.id, to.id, 100, "t-3")
    {:ok, _} = Transfers.transfer(from.id, to.id, 100, "t-3")
    assert Enum.count(events(), &(&1.topic == "transfer.completed")) == 1
  end
end
