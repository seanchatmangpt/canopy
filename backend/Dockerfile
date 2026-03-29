# Canopy Phoenix API (production release)
FROM hexpm/elixir:1.17.3-erlang-27.1.2-debian-bookworm-20241007 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN mix compile
RUN mix release

# --- Runtime ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl libstdc++6 curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --shell /usr/sbin/nologin canopy

WORKDIR /app

COPY --from=build --chown=canopy:canopy /app/_build/prod/rel/canopy ./
COPY --chown=canopy:canopy docker-entrypoint.sh /app/docker-entrypoint.sh

RUN chmod +x /app/docker-entrypoint.sh

USER canopy

ENV HOME=/app
ENV MIX_ENV=prod
ENV PHX_SERVER=true
# Must match docker-compose.yml PORT env and port mapping (9089).
ENV PORT=9089

EXPOSE 9089

ENTRYPOINT ["/app/docker-entrypoint.sh"]
