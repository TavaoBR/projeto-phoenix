defmodule Ledger.TransfersTest do
  use Ledger.DataCase, async: true

  alias Ledger.{Accounts, Transfers}

  defp account!(attrs \\ %{}) do
    doc = :rand.uniform(99_999_999_999) |> Integer.to_string() |> String.pad_leading(11, "0")
    {:ok, acc} = Accounts.open_account(Map.merge(%{owner_name: "Fulano", document: doc}, attrs))
    acc
  end

  defp balance(acc), do: Accounts.fetch_account(acc.id) |> elem(1) |> Map.get(:balance_cents)
  defp key, do: Ecto.UUID.generate()

  describe "open_account/1" do
    test "normaliza documento e começa com saldo zero" do
      {:ok, acc} = Accounts.open_account(%{owner_name: "Ana", document: "123.456.789-01"})
      assert acc.document == "12345678901"
      assert acc.balance_cents == 0
    end

    test "lista contas e retorna not_found para ids inexistentes ou inválidos" do
      acc = account!()
      assert acc.id in Enum.map(Accounts.list_accounts(), & &1.id)
      assert {:error, :not_found} = Accounts.fetch_account(Ecto.UUID.generate())
      assert {:error, :not_found} = Accounts.fetch_account("nao-e-uuid")
    end

    test "rejeita documento inválido e duplicado" do
      assert {:error, cs} = Accounts.open_account(%{owner_name: "Ana", document: "123"})
      assert errors_on(cs).document

      account!(%{document: "11122233344"})
      assert {:error, cs} = Accounts.open_account(%{owner_name: "Bruno", document: "11122233344"})
      assert "has already been taken" in errors_on(cs).document
    end
  end

  describe "deposit/3" do
    test "credita a conta" do
      acc = account!()
      assert {:ok, tx} = Transfers.deposit(acc.id, 10_000, key())
      assert tx.type == :deposit
      assert balance(acc) == 10_000
    end

    test "valida valor e conta" do
      acc = account!()
      assert {:error, :invalid_amount} = Transfers.deposit(acc.id, 0, key())
      assert {:error, :invalid_amount} = Transfers.deposit(acc.id, 10.5, key())
      assert {:error, :not_found} = Transfers.deposit(Ecto.UUID.generate(), 100, key())
      assert {:error, :not_found} = Transfers.deposit("abc", 100, key())
    end

    test "é idempotente" do
      acc = account!()
      k = key()
      {:ok, tx1} = Transfers.deposit(acc.id, 500, k)
      {:ok, tx2} = Transfers.deposit(acc.id, 500, k)
      assert tx1.id == tx2.id
      assert balance(acc) == 500
      assert {:error, :idempotency_conflict} = Transfers.deposit(acc.id, 999, k)
    end
  end

  describe "transfer/4" do
    setup do
      from = account!()
      to = account!()
      {:ok, _} = Transfers.deposit(from.id, 1_000, key())
      %{from: from, to: to}
    end

    test "move saldo entre contas", %{from: from, to: to} do
      assert {:ok, tx} = Transfers.transfer(from.id, to.id, 300, key())
      assert tx.from_account_id == from.id
      assert balance(from) == 700
      assert balance(to) == 300
    end

    test "nega saldo insuficiente sem alterar nada", %{from: from, to: to} do
      assert {:error, :insufficient_funds} = Transfers.transfer(from.id, to.id, 1_001, key())
      assert balance(from) == 1_000
      assert balance(to) == 0
    end

    test "regras de negócio", %{from: from} do
      usd = account!(%{currency: "USD"})
      assert {:error, :currency_mismatch} = Transfers.transfer(from.id, usd.id, 1, key())
      assert {:error, :same_account} = Transfers.transfer(from.id, from.id, 1, key())
    end

    test "aparece no extrato das duas contas", %{from: from, to: to} do
      {:ok, tx} = Transfers.transfer(from.id, to.id, 100, key())
      assert [%{id: id} | _] = Transfers.list_transactions(from.id)
      assert id == tx.id
      assert [%{id: ^id}] = Transfers.list_transactions(to.id)
    end
  end
end
