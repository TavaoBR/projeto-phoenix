# Testes de integração com RabbitMQ só rodam quando há um broker disponível
# (RABBITMQ_URL definido, como no CI). Sem ele, são pulados.
exclude = if System.get_env("RABBITMQ_URL"), do: [], else: [:rabbitmq]

ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Ledger.Repo, :manual)
