# Ledger API: Elixir + Phoenix (umbrella)

![CI](https://github.com/TavaoBR/projeto-phoenix/actions/workflows/ci.yml/badge.svg)

API REST de **contas, depósitos e transferências** escrita em Elixir/Phoenix com PostgreSQL.
É um projeto de estudo, mas trata os problemas que importam num sistema financeiro de verdade:
**consistência sob concorrência, idempotência, dinheiro sem ponto flutuante, eventos que nunca se perdem
e observabilidade.**

## Stack

| Área | Tecnologia |
|---|---|
| Linguagem / framework | Elixir 1.18, Phoenix 1.8 (API-only), estrutura **umbrella** |
| Banco | PostgreSQL 16 + Ecto (`Ecto.Multi`, locks de linha, constraints) |
| Mensageria | **RabbitMQ** (publisher confirms, DLQ) + **Broadway** (`broadway_rabbitmq`), padrão **transactional outbox** |
| Observabilidade | `:telemetry` → Prometheus (`/metrics`) → **Grafana**; **Datadog** (DogStatsD + logs); **Sentry** |
| Qualidade | ExUnit (concorrência + integração com RabbitMQ real), Credo `--strict`, `mix format` |
| CI/CD | **Jenkinsfile**, **Bitbucket Pipelines** e GitHub Actions (mesmos estágios), Docker multi-stage com `mix release` |

## Arquitetura

```
apps/
  ledger/         # Domínio e persistência: sem dependência de Phoenix nem de AMQP
    Ledger.Accounts        # contexto de contas
    Ledger.Transfers       # depósitos, transferências, extrato (grava o evento no outbox)
    Ledger.Outbox          # eventos pendentes + porta Ledger.Outbox.Publisher
    Ledger.Notifications   # notificações idempotentes
  ledger_events/  # Infra de mensageria: AMQPPublisher, OutboxRelay, pipeline Broadway
  ledger_web/     # Camada HTTP: controllers finos, FallbackController, telemetria
```

A separação em umbrella deixa explícita a fronteira **domínio ↔ infraestrutura**: `ledger_web` e
`ledger_events` dependem de `ledger`, nunca o contrário. O domínio só conhece o *behaviour*
`Ledger.Outbox.Publisher`; trocar RabbitMQ por SQS ou Kafka é escrever outro adapter. O domínio devolve `{:ok, _} | {:error, reason}` com motivos de negócio
(`:insufficient_funds`, `:currency_mismatch`...) e o `FallbackController` é o único lugar que traduz
isso para HTTP. Dá para trocar a entrega (fila, gRPC, CLI) sem tocar nas regras.

### Decisões de design

- **Dinheiro em centavos (`bigint`)**: nunca `float`. A API recebe e devolve `amount_cents` inteiro.
- **Atomicidade:** cada movimentação é um `Ecto.Multi`. Saldo e registro da transação mudam juntos ou nada muda.
- **Concorrência:** as contas envolvidas são travadas com `SELECT ... FOR UPDATE`, **sempre ordenadas por id**,
  o que evita deadlock quando A→B e B→A acontecem ao mesmo tempo. O saldo é atualizado com `inc`
  (atômico no banco), e um `CHECK (balance_cents >= 0)` serve de última linha de defesa.
- **Idempotência:** `POST /deposits` e `POST /transfers` exigem o header `Idempotency-Key`
  (índice único no banco). A retentativa com a mesma chave e os mesmos dados devolve a transação original;
  com dados diferentes, devolve `409 Conflict`. Também resolve a corrida em que duas requisições com a
  mesma chave chegam juntas.
- **Eventos sem perda (transactional outbox):** ver [Mensageria](#mensageria).
- **Validação na borda do domínio:** documento normalizado (CPF/CNPJ só com dígitos), moeda dentro de uma lista
  permitida, e o saldo nunca é aceito via API.

## Mensageria

```
POST /api/transfers
   │  Ecto.Multi: lock das contas → débito/crédito → transação → evento no outbox   (1 commit)
   ▼
outbox_events ──► OutboxRelay (FOR UPDATE SKIP LOCKED) ──► AMQPPublisher (confirms)
                                                              │
                                exchange topic `ledger.events`, routing key `transfer.completed`
                                                              ▼
                              fila `ledger.notifications` ──► Broadway ──► notifications
                                      │ (reject)
                                      ▼
                              `ledger.notifications.dlq`
```

- **Outbox:** o evento `transfer.completed`/`deposit.completed` é gravado **no mesmo `Ecto.Multi`** da
  movimentação. Se a transferência é confirmada, o evento existe; se der rollback, ele também some. Não
  existe a janela de "salvou no banco mas caiu antes de publicar".
- **Relay:** lê lotes com `FOR UPDATE SKIP LOCKED` (várias instâncias podem rodar juntas) e só marca o evento
  como publicado depois do **ack do broker** (publisher confirms). Se o RabbitMQ cair, o evento fica pendente,
  com `attempts`/`last_error`, e o publisher reconecta sozinho.
- **Entrega at-least-once:** cada mensagem leva o id do evento como `message_id`. O consumidor é
  **idempotente** (índice único `transaction_id + account_id`), então reprocessar não duplica nada.
- **Consumidor Broadway:** ack manual (a mensagem só sai da fila depois de gravada), concorrência e
  `prefetch_count` configurados. Mensagens inválidas vão para a **dead letter queue** em vez de travar a fila.

## Como rodar

### Com Docker (app + Postgres + RabbitMQ + Prometheus + Grafana)

```bash
docker compose up --build
```

- API: http://localhost:4000
- Métricas: http://localhost:4000/metrics
- Grafana: http://localhost:3000 (dashboard **Ledger API**, acesso anônimo)
- RabbitMQ: http://localhost:15672 (guest/guest)

### Com Datadog

```bash
DD_API_KEY=<sua chave> docker compose -f docker-compose.yml -f docker-compose.datadog.yml up --build
```

O agent recebe as métricas via DogStatsD e coleta os logs dos containers. O dashboard está em
[`ops/datadog/dashboard.json`](ops/datadog/dashboard.json) (Dashboards → New Dashboard → Import dashboard JSON).

### Local

Requer Elixir 1.18+, PostgreSQL (usuário/senha `postgres`, ou `DB_HOST`) e, para a mensageria, RabbitMQ
em `localhost:5672` (ou `RABBITMQ_URL`).

```bash
mix setup          # deps + cria e migra o banco
mix phx.server
mix test           # unitários; os testes de integração com RabbitMQ são pulados
RABBITMQ_URL=amqp://guest:guest@localhost:5672 mix test   # inclui integração com o broker real
mix precommit      # compile --warnings-as-errors + format + credo + test
```

## Endpoints

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/health` | Saúde da aplicação e do banco |
| `GET` | `/metrics` | Métricas no formato Prometheus |
| `POST` | `/api/accounts` | Abre conta `{owner_name, document, currency?}` |
| `GET` | `/api/accounts` | Lista contas |
| `GET` | `/api/accounts/:id` | Consulta conta e saldo |
| `GET` | `/api/accounts/:id/transactions?limit=&offset=` | Extrato paginado |
| `GET` | `/api/accounts/:id/notifications` | Notificações geradas pelo consumidor de eventos |
| `POST` | `/api/deposits` | `{account_id, amount_cents}` + `Idempotency-Key` |
| `POST` | `/api/transfers` | `{from_account_id, to_account_id, amount_cents}` + `Idempotency-Key` |

### Exemplo

```bash
curl -X POST localhost:4000/api/accounts -H 'content-type: application/json' \
  -d '{"owner_name":"Ana Souza","document":"390.533.447-05"}'

curl -X POST localhost:4000/api/deposits -H 'content-type: application/json' \
  -H 'Idempotency-Key: 7b1c...' -d '{"account_id":"<ID_ANA>","amount_cents":10000}'

curl -X POST localhost:4000/api/transfers -H 'content-type: application/json' \
  -H 'Idempotency-Key: 9f2e...' \
  -d '{"from_account_id":"<ID_ANA>","to_account_id":"<ID_BRUNO>","amount_cents":2500}'
```

Erros seguem um formato único:

```json
{ "error": { "code": "insufficient_funds", "message": "insufficient funds" } }
```

| Código | HTTP |
|---|---|
| `not_found` | 404 |
| `invalid_idempotency_key` | 400 |
| `invalid_amount`, `insufficient_funds`, `same_account`, `currency_mismatch`, validação | 422 |
| `idempotency_conflict` | 409 |

## Observabilidade

- `Ledger.Transfers` emite `:telemetry.span([:ledger, :transaction], ...)` com as tags `type` e `result`,
  publicado como histograma `ledger_transaction_stop_duration` (volume e latência por resultado).
  Isso mostra, por exemplo, quantas transferências estão falhando por saldo insuficiente.
- Latência HTTP por rota e status (`phoenix_router_dispatch_stop_duration`).
- Mensageria: `ledger_outbox_pending_count` (backlog), `ledger_outbox_dispatch_published/failed` e
  `ledger_notifications_consumed_count{result}`, com painéis no Grafana e no dashboard do Datadog.
- **Datadog:** as mesmas métricas vão para o agent via DogStatsD (`telemetry_metrics_statsd`, formato Datadog)
  quando `DD_AGENT_HOST` está definido; os logs dos containers são coletados pelo agent.
- Sentry captura exceções do Plug e erros logados quando `SENTRY_DSN` está definido.
- Logs com `request_id` em cada requisição.

## Testes

- `transfers_test.exs`: regras de negócio, validações e idempotência.
- `transfers_concurrency_test.exs`: 100 transferências cruzadas simultâneas (A↔B) sem deadlock nem perda
  de saldo, e 20 saques concorrentes numa conta que só cobre 10, que terminam com exatamente 10 aprovados e saldo zero.
- `outbox_test.exs` / `outbox_dispatch_test.exs`: um evento por movimentação confirmada, nenhum em falha ou
  retentativa, e reenvio quando o broker está fora.
- `notifications_test.exs` / `notification_pipeline_test.exs`: notificações e deduplicação, pipeline Broadway
  com `DummyProducer` e envio de mensagens inválidas para a DLQ.
- `*_integration_test.exs` (tag `:rabbitmq`, rodam no CI): fluxo ponta a ponta contra o RabbitMQ real
  (transferência → outbox → broker → Broadway → notificação), DLQ e **reconexão após queda do broker**.
- `api_test.exs`: fluxo HTTP completo, códigos de status e formato de erro.

## Próximos passos

- Adapter `Ledger.Outbox.Publisher` para **Amazon SQS** (`broadway_sqs` + LocalStack) ou **Kafka**.
- Suporte a **MySQL** (adapter MyXQL) para comparar o comportamento dos locks.
- Autenticação por API key e rate limiting.
- Exportar traces via OpenTelemetry (Datadog APM).
