defmodule LedgerWeb.AccountController do
  use LedgerWeb, :controller

  alias Ledger.Accounts
  alias LedgerWeb.JSONView

  action_fallback LedgerWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Accounts.list_accounts(), &JSONView.account/1)})
  end

  def create(conn, params) do
    with {:ok, account} <- Accounts.open_account(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/accounts/#{account.id}")
      |> json(%{data: JSONView.account(account)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, account} <- Accounts.fetch_account(id) do
      json(conn, %{data: JSONView.account(account)})
    end
  end
end
