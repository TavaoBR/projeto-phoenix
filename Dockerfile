# --- build -------------------------------------------------------------------
FROM hexpm/elixir:1.18.4-erlang-27.3.4-debian-bookworm-20260610-slim AS build

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

# Copia só o que define dependências primeiro para aproveitar cache de camadas.
COPY mix.exs mix.lock ./
COPY apps/ledger/mix.exs apps/ledger/
COPY apps/ledger_events/mix.exs apps/ledger_events/
COPY apps/ledger_web/mix.exs apps/ledger_web/
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile

COPY apps apps
COPY rel rel
COPY config/runtime.exs config/
RUN mix compile && mix release ledger_umbrella

# --- runtime -----------------------------------------------------------------
FROM debian:bookworm-20260610-slim

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 MIX_ENV=prod

WORKDIR /app
RUN chown nobody /app
COPY --from=build --chown=nobody:root /app/_build/prod/rel/ledger_umbrella ./
USER nobody

EXPOSE 4000
HEALTHCHECK --interval=10s --timeout=3s CMD curl -fs http://localhost:4000/health || exit 1
CMD ["/bin/sh", "-c", "/app/bin/migrate && /app/bin/server"]
