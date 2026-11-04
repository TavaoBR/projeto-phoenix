defmodule Ledger.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_name, :string, null: false
      add :document, :string, null: false
      add :currency, :string, size: 3, null: false, default: "BRL"
      add :balance_cents, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:document])
    create constraint(:accounts, :balance_non_negative, check: "balance_cents >= 0")
  end
end
