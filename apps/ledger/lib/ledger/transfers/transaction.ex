defmodule Ledger.Transfers.Transaction do
  @moduledoc "Registro imutável de movimentação (depósito ou transferência)."
  use Ecto.Schema

  alias Ledger.Accounts.Account

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "transactions" do
    field :type, Ecto.Enum, values: [:deposit, :transfer]
    field :amount_cents, :integer
    field :idempotency_key, :string
    belongs_to :from_account, Account
    belongs_to :to_account, Account

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
