defmodule LedgerEvents.AMQPPublisher do
  @moduledoc """
  Implementação de `Ledger.Outbox.Publisher` para RabbitMQ.

  Mantém uma conexão e um canal em modo *confirm*: `publish/3` só devolve `:ok`
  depois do ack do broker, então o outbox nunca marca como publicado um evento que
  o RabbitMQ não recebeu. Se a conexão cair, o processo reconecta com backoff e,
  até lá, `publish/3` devolve `{:error, :not_connected}` (o evento fica pendente).
  """
  use GenServer
  @behaviour Ledger.Outbox.Publisher

  require Logger

  @confirm_timeout 5_000
  @reconnect_ms 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Ledger.Outbox.Publisher
  def publish(topic, payload, message_id) do
    GenServer.call(__MODULE__, {:publish, topic, payload, message_id}, @confirm_timeout + 1_000)
  catch
    :exit, reason -> {:error, {:publisher_unavailable, reason}}
  end

  @impl GenServer
  def init(opts) do
    # O amqp_client faz link com quem abre a conexão: sem trap_exit, a queda do
    # broker derrubaria este processo junto em vez de disparar a reconexão.
    Process.flag(:trap_exit, true)
    {:ok, %{url: Keyword.fetch!(opts, :url), conn: nil, chan: nil}, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  @impl GenServer
  def handle_info(:connect, state), do: {:noreply, connect(state)}

  # Monitor e link avisam da mesma queda; só a primeira notificação reconecta.
  def handle_info({:DOWN, _, :process, pid, reason}, state),
    do: connection_lost(pid, reason, state)

  def handle_info({:EXIT, pid, reason}, %{conn: %{pid: pid}} = state),
    do: connection_lost(pid, reason, state)

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl GenServer
  def handle_call({:publish, _, _, _}, _from, %{chan: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:publish, topic, payload, message_id}, _from, %{chan: chan} = state) do
    {:reply, do_publish(chan, topic, payload, message_id), state}
  end

  defp connection_lost(pid, reason, %{conn: %{pid: pid}} = state) do
    Logger.warning("Conexão com RabbitMQ perdida: #{inspect(reason)}; reconectando")
    Process.send_after(self(), :connect, @reconnect_ms)
    {:noreply, %{state | conn: nil, chan: nil}}
  end

  defp connection_lost(_pid, _reason, state), do: {:noreply, state}

  defp do_publish(chan, topic, payload, message_id) do
    with :ok <-
           AMQP.Basic.publish(chan, LedgerEvents.exchange(), topic, Jason.encode!(payload),
             persistent: true,
             content_type: "application/json",
             message_id: message_id,
             type: topic,
             timestamp: System.os_time(:second)
           ),
         true <- AMQP.Confirm.wait_for_confirms(chan, @confirm_timeout) do
      :ok
    else
      false -> {:error, :nacked}
      :timeout -> {:error, :confirm_timeout}
      error -> {:error, error}
    end
  catch
    # O canal pode morrer entre a queda do broker e a chegada do :DOWN.
    :exit, reason -> {:error, {:channel_closed, reason}}
  end

  defp connect(state) do
    with {:ok, conn} <- AMQP.Connection.open(state.url),
         {:ok, chan} <- AMQP.Channel.open(conn),
         :ok <- AMQP.Confirm.select(chan),
         :ok <- LedgerEvents.declare_topology(chan) do
      Process.monitor(conn.pid)
      Logger.info("Publisher conectado ao RabbitMQ")
      %{state | conn: conn, chan: chan}
    else
      error ->
        Logger.warning(
          "RabbitMQ indisponível (#{inspect(error)}); nova tentativa em #{@reconnect_ms}ms"
        )

        Process.send_after(self(), :connect, @reconnect_ms)
        state
    end
  end
end
