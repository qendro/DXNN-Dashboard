# Build and runtime stage (single stage for simplicity)
FROM hexpm/elixir:1.16.3-erlang-26.2.5-alpine-3.19.1

# Install runtime dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    rebar3 \
    openssl \
    ncurses-libs \
    libstdc++ \
    aws-cli \
    bash \
    openssh-client \
    docker-cli \
    curl \
    jq

WORKDIR /app

# Copy everything
COPY . .

# Compile Erlang analyzer
WORKDIR /app/dxnn_analyzer
RUN rebar3 compile

# Install Elixir dependencies and compile
WORKDIR /app/dxnn_analyzer_web
RUN mix local.hex --force && \
    mix local.rebar --force && \
    MIX_ENV=prod mix deps.get && \
    MIX_ENV=prod mix deps.compile

# Install and build assets
WORKDIR /app/dxnn_analyzer_web/assets
RUN npm ci --prefer-offline --no-audit --progress=false && \
    npm run deploy

# Compile and digest assets
WORKDIR /app/dxnn_analyzer_web
RUN MIX_ENV=prod mix do compile, phx.digest

# Create data directory
RUN mkdir -p /app/data/MasterDatabase /app/data/s3_cache

ENV MIX_ENV=prod
ENV PORT=4000
ENV PHX_HOST=localhost

EXPOSE 4000

CMD ["mix", "phx.server"]
