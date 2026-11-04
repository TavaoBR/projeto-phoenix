defmodule LedgerWeb.MetricsController do
  @moduledoc "Endpoint de scrape do Prometheus, servido pelo próprio Bandit do Phoenix."
  use LedgerWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, LedgerWeb.Telemetry.scrape())
  end
end
