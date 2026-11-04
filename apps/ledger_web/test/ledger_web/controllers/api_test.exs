defmodule LedgerWeb.ApiTest do
  use LedgerWeb.ConnCase, async: true

  defp create_account(conn, doc) do
    conn
    |> post(~p"/api/accounts", %{owner_name: "Maria Silva", document: doc})
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp with_key(conn, key \\ Ecto.UUID.generate()),
    do: put_req_header(conn, "idempotency-key", key)

  test "GET /health", %{conn: conn} do
    assert %{"status" => "ok"} = conn |> get(~p"/health") |> json_response(200)
  end

  describe "accounts" do
    test "cria, consulta e lista", %{conn: conn} do
      id = create_account(conn, "52998224725")

      assert %{"data" => %{"balance_cents" => 0, "currency" => "BRL"}} =
               conn |> get(~p"/api/accounts/#{id}") |> json_response(200)

      assert %{"data" => [_ | _]} = conn |> get(~p"/api/accounts") |> json_response(200)
    end

    test "valida entrada e retorna 404", %{conn: conn} do
      assert %{"errors" => %{"document" => _, "owner_name" => _}} =
               conn |> post(~p"/api/accounts", %{}) |> json_response(422)

      assert %{"error" => %{"code" => "not_found"}} =
               conn |> get(~p"/api/accounts/nao-existe") |> json_response(404)
    end
  end

  describe "deposits e transfers" do
    setup %{conn: conn} do
      %{from: create_account(conn, "11111111111"), to: create_account(conn, "22222222222")}
    end

    test "fluxo completo com idempotência", %{conn: conn, from: from, to: to} do
      conn
      |> with_key()
      |> post(~p"/api/deposits", %{account_id: from, amount_cents: 10_000})
      |> json_response(201)

      body = %{from_account_id: from, to_account_id: to, amount_cents: 2_500}
      key = Ecto.UUID.generate()

      %{"data" => %{"id" => tx_id}} =
        conn |> with_key(key) |> post(~p"/api/transfers", body) |> json_response(201)

      # Retentativa do cliente com a mesma chave: mesma transação, sem débito duplo.
      assert %{"data" => %{"id" => ^tx_id}} =
               conn |> with_key(key) |> post(~p"/api/transfers", body) |> json_response(201)

      assert %{"data" => %{"balance_cents" => 7_500}} =
               conn |> get(~p"/api/accounts/#{from}") |> json_response(200)

      assert %{"data" => [%{"id" => ^tx_id}, _deposit]} =
               conn |> get(~p"/api/accounts/#{from}/transactions") |> json_response(200)

      assert %{"error" => %{"code" => "idempotency_conflict"}} =
               conn
               |> with_key(key)
               |> post(~p"/api/transfers", %{body | amount_cents: 1})
               |> json_response(409)
    end

    test "erros de negócio", %{conn: conn, from: from, to: to} do
      body = %{from_account_id: from, to_account_id: to, amount_cents: 1}

      assert %{"error" => %{"code" => "insufficient_funds"}} =
               conn |> with_key() |> post(~p"/api/transfers", body) |> json_response(422)

      assert %{"error" => %{"code" => "invalid_idempotency_key"}} =
               conn |> post(~p"/api/transfers", body) |> json_response(400)

      assert %{"error" => %{"code" => "invalid_amount"}} =
               conn
               |> with_key()
               |> post(~p"/api/deposits", %{account_id: from, amount_cents: "100"})
               |> json_response(422)
    end
  end
end
