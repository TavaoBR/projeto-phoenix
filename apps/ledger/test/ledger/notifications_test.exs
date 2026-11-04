defmodule Ledger.NotificationsTest do
  use Ledger.DataCase, async: true

  alias Ledger.{Accounts, Notifications, Transfers}
  alias Ledger.Outbox.Event

  defp account!(doc) do
    {:ok, acc} = Accounts.open_account(%{owner_name: "Fulano", document: doc})
    acc
  end

  defp payload(tx), do: Event.from_transaction(tx).payload

  test "transferência notifica débito na origem e crédito no destino" do
    from = account!("30000000001")
    to = account!("30000000002")
    {:ok, _} = Transfers.deposit(from.id, 10_000, "d")
    {:ok, tx} = Transfers.transfer(from.id, to.id, 1_250, "t")

    assert {:ok, 2} = Notifications.record_event(payload(tx))

    assert [%{kind: :debit, message: "Transferência de R$ 12,50 enviada"}] =
             Notifications.list_for_account(from.id)

    assert [%{kind: :credit, amount_cents: 1_250}] = Notifications.list_for_account(to.id)
  end

  test "reprocessar o mesmo evento não duplica notificações" do
    acc = account!("30000000003")
    {:ok, tx} = Transfers.deposit(acc.id, 905, "d2")

    assert {:ok, 1} = Notifications.record_event(payload(tx))
    assert {:ok, 0} = Notifications.record_event(payload(tx))
    assert [%{message: "Depósito de R$ 9,05 recebido"}] = Notifications.list_for_account(acc.id)
  end

  test "rejeita evento malformado" do
    assert {:error, :invalid_event} = Notifications.record_event(%{"type" => "outro"})
  end
end
