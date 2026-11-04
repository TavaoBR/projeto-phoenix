defmodule Ledger.Outbox do
  @moduledoc """
  Leitura e despacho dos eventos pendentes do outbox.

  `dispatch/2` trava um lote com `FOR UPDATE SKIP LOCKED`: várias instâncias do
  relay podem rodar ao mesmo tempo sem publicar o mesmo evento duas vezes no mesmo
  ciclo. A entrega é *at-least-once*: se o processo cair depois de o broker
  confirmar e antes do commit, o evento é reenviado; por isso cada mensagem leva o
  id do evento como `message_id`, e os consumidores devem ser idempotentes.
  """
  import Ecto.Query

  alias Ledger.Outbox.Event
  alias Ledger.Repo

  @type summary :: %{published: non_neg_integer(), failed: non_neg_integer()}

  @spec dispatch(module(), pos_integer()) :: summary()
  def dispatch(publisher, batch_size \\ 100) do
    {:ok, summary} =
      Repo.transaction(fn ->
        pending(batch_size)
        |> Enum.map(&publish(&1, publisher))
        |> Enum.frequencies()
        |> then(&%{published: Map.get(&1, :published, 0), failed: Map.get(&1, :failed, 0)})
      end)

    :telemetry.execute([:ledger, :outbox, :dispatch], summary, %{})
    summary
  end

  @spec pending_count() :: non_neg_integer()
  def pending_count do
    Repo.aggregate(from(e in Event, where: is_nil(e.published_at)), :count)
  end

  defp pending(limit) do
    Event
    |> where([e], is_nil(e.published_at))
    |> order_by(:inserted_at)
    |> limit(^limit)
    |> lock("FOR UPDATE SKIP LOCKED")
    # Consulta de polling (roda a cada segundo): fora do log para não poluí-lo.
    |> Repo.all(log: false)
  end

  defp publish(%Event{} = event, publisher) do
    case publisher.publish(event.topic, event.payload, event.id) do
      :ok ->
        mark(event, published_at: DateTime.utc_now(), last_error: nil)
        :published

      {:error, reason} ->
        mark(event, attempts: event.attempts + 1, last_error: inspect(reason))
        :failed
    end
  end

  defp mark(event, changes) do
    Event |> where(id: ^event.id) |> Repo.update_all(set: changes)
  end
end
