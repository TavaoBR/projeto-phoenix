defmodule Ledger.Transfers do
  @moduledoc """
  Movimentações financeiras.

  Garantias:
    * atomicidade via `Ecto.Multi` (saldo e registro mudam juntos ou nada muda);
    * consistência sob concorrência com `SELECT ... FOR UPDATE`, travando as contas
      sempre na mesma ordem (por id) para evitar deadlocks;
    * idempotência: repetir a mesma `idempotency_key` com os mesmos dados devolve a
      transação original em vez de movimentar dinheiro de novo;
    * entrega de eventos: um `Ledger.Outbox.Event` é gravado no mesmo `Multi`, então
      todo movimento confirmado gera exatamente um evento a ser publicado.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Ledger.Accounts.Account
  alias Ledger.Outbox.Event
  alias Ledger.Repo
  alias Ledger.Transfers.Transaction

  @type error ::
          :not_found
          | :invalid_amount
          | :invalid_idempotency_key
          | :same_account
          | :insufficient_funds
          | :currency_mismatch
          | :idempotency_conflict

  @spec deposit(term(), term(), term()) :: {:ok, Transaction.t()} | {:error, error()}
  def deposit(account_id, amount_cents, idempotency_key) do
    with :ok <- validate_amount(amount_cents),
         :ok <- validate_key(idempotency_key),
         {:ok, [to_id]} <- cast_ids([account_id]) do
      params = %{type: :deposit, from: nil, to: to_id, amount: amount_cents}

      run_idempotent(idempotency_key, params, fn -> deposit_multi(params, idempotency_key) end)
    end
  end

  @spec transfer(term(), term(), term(), term()) :: {:ok, Transaction.t()} | {:error, error()}
  def transfer(from_id, to_id, amount_cents, idempotency_key) do
    with :ok <- validate_amount(amount_cents),
         :ok <- validate_key(idempotency_key),
         {:ok, [from_id, to_id]} <- cast_ids([from_id, to_id]),
         :ok <- if(from_id == to_id, do: {:error, :same_account}, else: :ok) do
      params = %{type: :transfer, from: from_id, to: to_id, amount: amount_cents}

      run_idempotent(idempotency_key, params, fn -> transfer_multi(params, idempotency_key) end)
    end
  end

  @doc "Extrato paginado de uma conta (mais recentes primeiro)."
  @spec list_transactions(Ecto.UUID.t(), keyword()) :: [Transaction.t()]
  def list_transactions(account_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> min(100) |> max(1)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    Transaction
    |> where([t], t.from_account_id == ^account_id or t.to_account_id == ^account_id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  # -- internos ---------------------------------------------------------------

  defp deposit_multi(%{to: to_id, amount: amount}, key) do
    Multi.new()
    |> Multi.run(:accounts, fn repo, _ -> lock_accounts(repo, [to_id]) end)
    |> Multi.update_all(:credit, credit(to_id, amount), [])
    |> Multi.insert(:transaction, %Transaction{
      type: :deposit,
      amount_cents: amount,
      to_account_id: to_id,
      idempotency_key: key
    })
    |> Multi.insert(:outbox, &Event.from_transaction(&1.transaction))
  end

  defp transfer_multi(%{from: from_id, to: to_id, amount: amount}, key) do
    Multi.new()
    |> Multi.run(:accounts, fn repo, _ -> lock_accounts(repo, [from_id, to_id]) end)
    |> Multi.run(:check, fn _, %{accounts: accounts} ->
      check_transfer(accounts[from_id], accounts[to_id], amount)
    end)
    |> Multi.update_all(:debit, credit(from_id, -amount), [])
    |> Multi.update_all(:credit, credit(to_id, amount), [])
    |> Multi.insert(:transaction, %Transaction{
      type: :transfer,
      amount_cents: amount,
      from_account_id: from_id,
      to_account_id: to_id,
      idempotency_key: key
    })
    |> Multi.insert(:outbox, &Event.from_transaction(&1.transaction))
  end

  defp validate_amount(amount) when is_integer(amount) and amount > 0, do: :ok
  defp validate_amount(_), do: {:error, :invalid_amount}

  defp validate_key(key) when is_binary(key) and byte_size(key) in 1..255, do: :ok
  defp validate_key(_), do: {:error, :invalid_idempotency_key}

  defp run_idempotent(key, params, build_multi) do
    case find_by_key(key) do
      nil -> execute(key, params, build_multi)
      tx -> match_replay(tx, params)
    end
  end

  defp execute(key, params, build_multi) do
    :telemetry.span([:ledger, :transaction], %{type: params.type}, fn ->
      result =
        case Repo.transaction(build_multi.()) do
          {:ok, %{transaction: tx}} -> {:ok, tx}
          {:error, :accounts, reason, _} -> {:error, reason}
          {:error, :check, reason, _} -> {:error, reason}
          # Corrida entre duas requisições com a mesma chave: a segunda perde no unique index.
          {:error, :transaction, _changeset, _} -> key |> find_by_key() |> match_replay(params)
        end

      {result, %{type: params.type, result: result_tag(result)}}
    end)
  end

  defp result_tag({:ok, _}), do: :ok
  defp result_tag({:error, reason}), do: reason

  defp match_replay(%Transaction{} = tx, params) do
    same? =
      tx.type == params.type and tx.amount_cents == params.amount and
        tx.to_account_id == params.to and tx.from_account_id == params.from

    if same?, do: {:ok, tx}, else: {:error, :idempotency_conflict}
  end

  defp match_replay(nil, _), do: {:error, :idempotency_conflict}

  defp find_by_key(key), do: Repo.get_by(Transaction, idempotency_key: key)

  defp lock_accounts(repo, ids) do
    accounts =
      Account
      |> where([a], a.id in ^ids)
      |> order_by(:id)
      |> lock("FOR UPDATE")
      |> repo.all()
      |> Map.new(&{&1.id, &1})

    if map_size(accounts) == length(ids), do: {:ok, accounts}, else: {:error, :not_found}
  end

  defp cast_ids(ids) do
    ids
    |> Enum.reduce_while([], fn id, acc ->
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> {:cont, [uuid | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> {:error, :not_found}
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp check_transfer(%Account{currency: c1}, %Account{currency: c2}, _) when c1 != c2,
    do: {:error, :currency_mismatch}

  defp check_transfer(%Account{balance_cents: balance}, _to, amount) when balance < amount,
    do: {:error, :insufficient_funds}

  defp check_transfer(_from, _to, _amount), do: {:ok, :ok}

  defp credit(id, delta) do
    from(a in Account,
      where: a.id == ^id,
      update: [inc: [balance_cents: ^delta], set: [updated_at: ^DateTime.utc_now()]]
    )
  end
end
