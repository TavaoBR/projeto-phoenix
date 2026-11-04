defmodule LedgerWeb.TransactionController do
  use LedgerWeb, :controller

  alias Ledger.{Accounts, Transfers}
  alias LedgerWeb.JSONView

  action_fallback LedgerWeb.FallbackController

  def index(conn, %{"id" => id} = params) do
    with {:ok, account} <- Accounts.fetch_account(id) do
      opts = [limit: int_param(params, "limit", 50), offset: int_param(params, "offset", 0)]
      txs = Transfers.list_transactions(account.id, opts)
      json(conn, %{data: Enum.map(txs, &JSONView.transaction/1), meta: Map.new(opts)})
    end
  end

  def deposit(conn, params) do
    with {:ok, tx} <-
           Transfers.deposit(params["account_id"], params["amount_cents"], idempotency_key(conn)) do
      created(conn, tx)
    end
  end

  def transfer(conn, params) do
    with {:ok, tx} <-
           Transfers.transfer(
             params["from_account_id"],
             params["to_account_id"],
             params["amount_cents"],
             idempotency_key(conn)
           ) do
      created(conn, tx)
    end
  end

  defp created(conn, tx) do
    conn |> put_status(:created) |> json(%{data: JSONView.transaction(tx)})
  end

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key | _] -> key
      [] -> nil
    end
  end

  defp int_param(params, key, default) do
    case Integer.parse(params[key] || "") do
      {n, ""} -> n
      _ -> default
    end
  end
end
