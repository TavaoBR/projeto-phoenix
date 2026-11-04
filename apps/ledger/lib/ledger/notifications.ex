defmodule Ledger.Notifications do
  @moduledoc """
  Notificações geradas a partir dos eventos `*.completed`.

  `record_event/1` é idempotente: o índice único (transaction_id, account_id) com
  `on_conflict: :nothing` torna seguro reprocessar a mesma mensagem.
  """
  import Ecto.Query

  alias Ledger.Notifications.Notification
  alias Ledger.Repo

  @spec record_event(map()) :: {:ok, non_neg_integer()} | {:error, :invalid_event}
  def record_event(%{"transaction_id" => tx_id, "type" => type, "amount_cents" => amount} = event)
      when type in ["deposit", "transfer"] and is_integer(amount) do
    now = DateTime.utc_now()

    rows =
      event
      |> entries(type, amount)
      |> Enum.map(fn {account_id, kind, message} ->
        %{
          id: Ecto.UUID.generate(),
          account_id: account_id,
          transaction_id: tx_id,
          kind: kind,
          amount_cents: amount,
          message: message,
          inserted_at: now
        }
      end)

    {count, _} =
      Repo.insert_all(Notification, rows,
        on_conflict: :nothing,
        conflict_target: [:transaction_id, :account_id]
      )

    {:ok, count}
  end

  def record_event(_), do: {:error, :invalid_event}

  @spec list_for_account(Ecto.UUID.t(), pos_integer()) :: [Notification.t()]
  def list_for_account(account_id, limit \\ 50) do
    Notification
    |> where(account_id: ^account_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp entries(%{"to_account_id" => to}, "deposit", amount),
    do: [{to, :credit, "Depósito de #{format(amount)} recebido"}]

  defp entries(%{"from_account_id" => from, "to_account_id" => to}, "transfer", amount),
    do: [
      {from, :debit, "Transferência de #{format(amount)} enviada"},
      {to, :credit, "Transferência de #{format(amount)} recebida"}
    ]

  defp format(cents) do
    reais = div(cents, 100)
    centavos = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "R$ #{reais},#{centavos}"
  end
end
