defmodule LedgerWeb.JSONView do
  @moduledoc "Serialização explícita: só expõe os campos públicos da API."

  def account(a) do
    %{
      id: a.id,
      owner_name: a.owner_name,
      document: a.document,
      currency: a.currency,
      balance_cents: a.balance_cents,
      inserted_at: a.inserted_at
    }
  end

  def transaction(t) do
    %{
      id: t.id,
      type: t.type,
      amount_cents: t.amount_cents,
      from_account_id: t.from_account_id,
      to_account_id: t.to_account_id,
      inserted_at: t.inserted_at
    }
  end
end
