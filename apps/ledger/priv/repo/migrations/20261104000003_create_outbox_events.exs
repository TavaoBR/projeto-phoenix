defmodule Ledger.Repo.Migrations.CreateOutboxEvents do
  use Ecto.Migration

  def change do
    create table(:outbox_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :topic, :string, null: false
      add :payload, :map, null: false
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :published_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # O relay só lê eventos pendentes, em ordem de criação.
    create index(:outbox_events, [:inserted_at],
             where: "published_at IS NULL",
             name: :outbox_pending
           )
  end
end
