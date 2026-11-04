defmodule LedgerWeb.NotificationController do
  use LedgerWeb, :controller

  alias Ledger.{Accounts, Notifications}
  alias LedgerWeb.JSONView

  action_fallback LedgerWeb.FallbackController

  def index(conn, %{"id" => id}) do
    with {:ok, account} <- Accounts.fetch_account(id) do
      notifications = Notifications.list_for_account(account.id)
      json(conn, %{data: Enum.map(notifications, &JSONView.notification/1)})
    end
  end
end
