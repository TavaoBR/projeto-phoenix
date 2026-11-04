# Ledger API: Elixir + Phoenix (umbrella)

![CI](https://github.com/TavaoBR/projeto-phoenix/actions/workflows/ci.yml/badge.svg)

API REST de **contas, depósitos e transferências** escrita em Elixir/Phoenix com PostgreSQL.
É um projeto de estudo, mas trata os problemas que importam num sistema financeiro de verdade:
**consistência sob concorrência, idempotência, dinheiro sem ponto flutuante e observabilidade.**

## Stack

| Área | Tecnologia |
|---|---|
| Linguagem / framework | Elixir 1.18, Phoenix 1.8 (API-only), estrutura **umbrella** |
| Banco | PostgreSQL 16 + Ecto (`Ecto.Multi`, locks de linha, constraints) |
| Observabilidade | `:telemetry` → Prometheus (`/metrics`) → **Grafana** (dashboard provisionado), **Sentry** |
| Qualidade | ExUnit (incl. testes de concorrência), Credo `--strict`, `mix format` |
| CI/CD | **Jenkinsfile** + GitHub Actions (mesmos estágios), Docker multi-stage com `mix release` |

## Arquitetura

```
apps/
  ledger/       # Domínio e persistência: sem nenhuma dependência de Phoenix
    Ledger.Accounts      # contexto de contas
    Ledger.Transfers     # depósitos, transferências, extrato
  ledger_web/   # Camada HTTP: controllers finos, FallbackController, telemetria
```

A separação em umbrella deixa explícita a fronteira **domínio ↔ entrega**: `ledger_web` depende de
`ledger`, nunca o contrário. O domínio devolve `{:ok, _} | {:error, reason}` com motivos de negócio
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
- **Validação na borda do domínio:** documento normalizado (CPF/CNPJ só com dígitos), moeda dentro de uma lista
  permitida, e o saldo nunca é aceito via API.

## Como rodar

### Com Docker (app + Postgres + Prometheus + Grafana)

```bash
docker compose up --build
```

- API: http://localhost:4000
- Métricas: http://localhost:4000/metrics
- Grafana: http://localhost:3000 (dashboard **Ledger API**, acesso anônimo)

### Local

Requer Elixir 1.18+ e PostgreSQL (usuário/senha `postgres`, ou `DB_HOST` para outro host).

```bash
mix setup          # deps + cria e migra o banco
mix phx.server
mix test           # 19 testes, incluindo concorrência
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
- Sentry captura exceções do Plug e erros logados quando `SENTRY_DSN` está definido.
- Logs com `request_id` em cada requisição.

## Testes

- `transfers_test.exs`: regras de negócio, validações e idempotência.
- `transfers_concurrency_test.exs`: 100 transferências cruzadas simultâneas (A↔B) sem deadlock nem perda
  de saldo, e 20 saques concorrentes numa conta que só cobre 10, que terminam com exatamente 10 aprovados e saldo zero.
- `api_test.exs`: fluxo HTTP completo, códigos de status e formato de erro.

## Próximos passos

- Publicar eventos `transaction.created` em **RabbitMQ/Kafka** (Broadway) usando outbox pattern.
- Suporte a **MySQL** (adapter MyXQL) para comparar o comportamento dos locks.
- Autenticação por API key e rate limiting.
- Exportar traces via OpenTelemetry (Datadog APM).
