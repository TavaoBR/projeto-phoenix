defmodule LedgerWeb.Router do
  use LedgerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  get "/health", LedgerWeb.HealthController, :show
  get "/metrics", LedgerWeb.MetricsController, :index

  scope "/api", LedgerWeb do
    pipe_through :api

    resources "/accounts", AccountController, only: [:index, :create, :show]
    get "/accounts/:id/transactions", TransactionController, :index
    get "/accounts/:id/notifications", NotificationController, :index
    post "/deposits", TransactionController, :deposit
    post "/transfers", TransactionController, :transfer
  end
end
