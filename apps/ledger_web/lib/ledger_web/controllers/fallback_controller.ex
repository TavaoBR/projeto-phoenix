defmodule LedgerWeb.FallbackController do
  @moduledoc "Traduz erros de domínio (`{:error, reason}`) em respostas HTTP."
  use LedgerWeb, :controller

  @errors %{
    not_found: {:not_found, "resource not found"},
    invalid_amount: {:unprocessable_entity, "amount_cents must be a positive integer"},
    invalid_idempotency_key: {:bad_request, "Idempotency-Key header is required"},
    same_account: {:unprocessable_entity, "cannot transfer to the same account"},
    insufficient_funds: {:unprocessable_entity, "insufficient funds"},
    currency_mismatch: {:unprocessable_entity, "accounts have different currencies"},
    idempotency_conflict: {:conflict, "Idempotency-Key already used with different parameters"}
  }

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
  end

  def call(conn, {:error, reason}) when is_map_key(@errors, reason) do
    {status, message} = Map.fetch!(@errors, reason)

    conn
    |> put_status(status)
    |> json(%{error: %{code: reason, message: message}})
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
