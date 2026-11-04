defmodule LedgerEvents.EventsCase do
  @moduledoc "Caso de teste com sandbox do banco compartilhado entre processos do teste."
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Ledger.Repo
      import LedgerEvents.EventsCase
    end
  end

  setup tags do
    # Relay e pipeline rodam em outros processos: o sandbox precisa ser compartilhado.
    pid = Sandbox.start_owner!(Ledger.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc "Abre uma conta com documento aleatório."
  def account!(name \\ "Fulano") do
    doc = :rand.uniform(99_999_999_999) |> Integer.to_string() |> String.pad_leading(11, "0")
    {:ok, acc} = Ledger.Accounts.open_account(%{owner_name: name, document: doc})
    acc
  end
end
