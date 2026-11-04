defmodule Ledger.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :amount_cents, :bigint, null: false
      add :idempotency_key, :string, null: false
      add :from_account_id, references(:accounts, type: :binary_id, on_delete: :restrict)

      add :to_account_id, references(:accounts, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:transactions, [:idempotency_key])
    create index(:transactions, [:from_account_id])
    create index(:transactions, [:to_account_id])
    create constraint(:transactions, :amount_positive, check: "amount_cents > 0")
  end
end
