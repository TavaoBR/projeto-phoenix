defmodule Ledger.TransfersConcurrencyTest do
  # Sandbox em modo compartilhado e sem async: as tasks precisam de conexões reais
  # concorrentes para exercitar os locks de linha.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ledger.{Accounts, Repo, Transfers}

  # Módulos síncronos rodam depois dos assíncronos, então o TRUNCATE é seguro.
  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.query!("TRUNCATE outbox_events, transactions, accounts")
    end)
  end

  # Cada task usa uma conexão real (fora da transação de sandbox).
  defp concurrently(enum, max, fun) do
    enum
    |> Task.async_stream(
      fn i ->
        :ok = Sandbox.checkout(Repo, sandbox: false)
        fun.(i)
      end,
      max_concurrency: max,
      timeout: 15_000
    )
    |> Enum.map(fn {:ok, r} -> r end)
  end

  test "transferências cruzadas simultâneas não perdem dinheiro nem dão deadlock" do
    {:ok, a} = Accounts.open_account(%{owner_name: "Alice", document: "00000000001"})
    {:ok, b} = Accounts.open_account(%{owner_name: "Bruno", document: "00000000002"})
    {:ok, _} = Transfers.deposit(a.id, 5_000, "seed-a")
    {:ok, _} = Transfers.deposit(b.id, 5_000, "seed-b")

    results =
      concurrently(1..100, 10, fn i ->
        {from, to} = if rem(i, 2) == 0, do: {a, b}, else: {b, a}
        Transfers.transfer(from.id, to.id, 100, "t-#{i}")
      end)

    assert Enum.all?(results, &match?({:ok, _}, &1))

    {:ok, a} = Accounts.fetch_account(a.id)
    {:ok, b} = Accounts.fetch_account(b.id)
    assert a.balance_cents + b.balance_cents == 10_000
    assert a.balance_cents == 5_000
  end

  test "saques concorrentes nunca deixam saldo negativo" do
    {:ok, a} = Accounts.open_account(%{owner_name: "Alice", document: "00000000003"})
    {:ok, b} = Accounts.open_account(%{owner_name: "Bruno", document: "00000000004"})
    {:ok, _} = Transfers.deposit(a.id, 1_000, "seed")

    ok_count =
      concurrently(1..20, 20, &Transfers.transfer(a.id, b.id, 100, "w-#{&1}"))
      |> Enum.count(&match?({:ok, _}, &1))

    assert ok_count == 10
    {:ok, a} = Accounts.fetch_account(a.id)
    assert a.balance_cents == 0
  end
end
