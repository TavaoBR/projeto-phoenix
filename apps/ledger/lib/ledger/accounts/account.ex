defmodule Ledger.Accounts.Account do
  @moduledoc "Conta com saldo armazenado em centavos (inteiro) para evitar erros de ponto flutuante."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @currencies ~w(BRL USD EUR)

  @type t :: %__MODULE__{}

  schema "accounts" do
    field :owner_name, :string
    field :document, :string
    field :currency, :string, default: "BRL"
    field :balance_cents, :integer, default: 0

    timestamps()
  end

  @doc "Changeset de abertura de conta. O saldo nunca é aceito via API."
  def create_changeset(account, attrs) do
    account
    |> cast(attrs, [:owner_name, :document, :currency])
    |> validate_required([:owner_name, :document])
    |> update_change(:document, &String.replace(&1, ~r/\D/, ""))
    |> validate_length(:owner_name, min: 2, max: 120)
    |> validate_format(:document, ~r/^(\d{11}|\d{14})$/,
      message: "must be a CPF (11 digits) or CNPJ (14 digits)"
    )
    |> validate_inclusion(:currency, @currencies)
    |> unique_constraint(:document)
  end
end
