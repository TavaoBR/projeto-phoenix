defmodule Ledger.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :transaction_id, references(:transactions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :amount_cents, :bigint, null: false
      add :message, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Entrega at-least-once: a mesma mensagem reprocessada não gera notificação duplicada.
    create unique_index(:notifications, [:transaction_id, :account_id])
    create index(:notifications, [:account_id, :inserted_at])
  end
end
