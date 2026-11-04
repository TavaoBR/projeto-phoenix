defmodule LedgerWeb.HealthController do
  use LedgerWeb, :controller

  alias Ecto.Adapters.SQL

  def show(conn, _params) do
    case SQL.query(Ledger.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok", database: "up"})

      {:error, _} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "degraded", database: "down"})
    end
  end
end
