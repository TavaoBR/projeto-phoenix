defmodule Ledger.Notifications.Notification do
  @moduledoc "Aviso ao titular de uma conta sobre crédito ou débito."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "notifications" do
    field :account_id, :binary_id
    field :transaction_id, :binary_id
    field :kind, Ecto.Enum, values: [:credit, :debit]
    field :amount_cents, :integer
    field :message, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
