defmodule LedgerEvents.OutboxRelay do
  @moduledoc """
  Processo que drena o outbox periodicamente usando o publisher configurado.

  Enquanto um lote vem cheio, despacha de novo sem esperar (alcança o backlog
  rápido); quando o outbox esvazia, volta ao intervalo normal de polling.
  """
  use GenServer

  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    state = %{
      publisher: Keyword.fetch!(opts, :publisher),
      interval: Keyword.get(opts, :interval, 1_000),
      batch_size: Keyword.get(opts, :batch_size, 100)
    }

    {:ok, schedule(state, state.interval)}
  end

  @impl true
  def handle_info(:dispatch, state) do
    %{published: published, failed: failed} =
      Ledger.Outbox.dispatch(state.publisher, state.batch_size)

    if failed > 0,
      do: Logger.warning("Outbox: #{failed} evento(s) falharam; nova tentativa no próximo ciclo")

    next = if published == state.batch_size, do: 0, else: state.interval
    {:noreply, schedule(state, next)}
  end

  defp schedule(state, ms) do
    Process.send_after(self(), :dispatch, ms)
    state
  end
end
