defmodule Ledger.Accounts do
  @moduledoc "Contexto de contas."
  import Ecto.Query

  alias Ledger.Accounts.Account
  alias Ledger.Repo

  @spec open_account(map()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def open_account(attrs) do
    %Account{}
    |> Account.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec fetch_account(term()) :: {:ok, Account.t()} | {:error, :not_found}
  def fetch_account(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Account{} = account <- Repo.get(Account, uuid) do
      {:ok, account}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec list_accounts() :: [Account.t()]
  def list_accounts do
    Account |> order_by(:inserted_at) |> Repo.all()
  end
end
