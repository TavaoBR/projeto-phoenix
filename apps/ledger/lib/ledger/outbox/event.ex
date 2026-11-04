defmodule Ledger.Outbox.Event do
  @moduledoc """
  Evento de domínio aguardando publicação (padrão transactional outbox).

  É gravado na mesma transação do banco que a movimentação: se a transferência
  for confirmada, o evento existe; se der rollback, o evento também some.
  """
  use Ecto.Schema

  alias Ledger.Transfers.Transaction

  @primary_key {:id, :binary_id, autogenerate: true}

  @type t :: %__MODULE__{}

  schema "outbox_events" do
    field :topic, :string
    field :payload, :map
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :published_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Monta o evento `<tipo>.completed` a partir de uma transação confirmada."
  @spec from_transaction(Transaction.t()) :: t()
  def from_transaction(%Transaction{} = tx) do
    %__MODULE__{
      topic: "#{tx.type}.completed",
      payload: %{
        "transaction_id" => tx.id,
        "type" => to_string(tx.type),
        "amount_cents" => tx.amount_cents,
        "from_account_id" => tx.from_account_id,
        "to_account_id" => tx.to_account_id,
        "occurred_at" => DateTime.to_iso8601(tx.inserted_at)
      }
    }
  end
end
