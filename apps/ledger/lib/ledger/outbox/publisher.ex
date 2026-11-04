defmodule Ledger.Outbox.Publisher do
  @moduledoc """
  Porta de saída para publicar eventos do outbox.

  O domínio só conhece este contrato; a implementação concreta (RabbitMQ, SQS,
  Kafka...) vive fora do app `ledger`.
  """

  @doc """
  Publica um evento. `:ok` só deve ser retornado depois que o broker confirmou o
  recebimento: é isso que permite marcar o evento como publicado com segurança.
  """
  @callback publish(topic :: String.t(), payload :: map(), message_id :: String.t()) ::
              :ok | {:error, term()}
end
