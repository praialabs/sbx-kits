FROM docker/sandbox-templates:shell-docker AS elixir-docker

# Set locale to prevent warnings in Elixir
ENV LANG=C.UTF-8

USER root

# Keep apt cache for faster builds
RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
  echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install compile and watch dependencies (git, curl, unzip, openssl, netbase, etc. are pre-installed in the base image)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache-ubuntu-26-resolute \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=apt-lib-ubuntu-26-resolute \
    apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      build-essential \
      inotify-tools \
      libncurses-dev \
      libreadline-dev \
      m4 \
      neovim

USER agent

# Configure system-wide sandbox environment (POSIX-compliant file)
RUN cat <<'EOF' >> /etc/sandbox-persistent.sh
export EDITOR="nvim"
export VISUAL="nvim"

# Prepend asdf shims to PATH for all users
export PATH="/home/agent/.asdf/shims:$PATH"

# Load asdf completions (only for interactive shells)
if [ -n "$BASH_VERSION" ] && [ -t 1 ]; then
  eval "$(asdf completion bash)"
fi

# Compile flags for Erlang/OTP or native builds
export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-wx --without-odbc"
export MAKEFLAGS="-j$(nproc)"

# Enable shell history in Erlang and Elixir shells
export ERL_AFLAGS="-kernel shell_history enabled"

# Optimize Mix parallel dependency compilation (ncpu/2 clamped to [1, 4])
# - https://mix.hexdocs.pm/Mix.Tasks.Deps.Compile.html#module-compiling-dependencies-across-multiple-os-processes
# - https://elixir-lang.org/blog/2025/10/16/elixir-v1-19-0-released/#:~:text=Empirical%20testing%20shows%20that%20setting%20it%20to%20half%20of%20the%20number%20of%20cores%20on%20your%20machine%20is%20enough%20to%20maximize%20resource%20usage
CORES=$(nproc)
PARTITIONS=$((CORES / 2))
if [ "$PARTITIONS" -lt 1 ]; then
  PARTITIONS=1
elif [ "$PARTITIONS" -gt 4 ]; then
  PARTITIONS=4
fi
export MIX_OS_DEPS_COMPILE_PARTITION_COUNT=$PARTITIONS
EOF

# Install asdf using Go (installed in the base image)
ARG ASDF_VERSION=latest
RUN mkdir -p /home/agent/.local/bin /home/agent/.asdf/shims && \
    GOBIN=/home/agent/.local/bin go install github.com/asdf-vm/asdf/cmd/asdf@${ASDF_VERSION} && \
    go clean -modcache -cache && \
    rm -rf /home/agent/go /home/agent/.cache/go-build

# Add asdf plugins
RUN asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git && \
    asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git && \
    asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git

# Install Erlang/OTP
ARG ERLANG_VERSION=latest
RUN . /etc/sandbox-persistent.sh && \
    asdf install erlang "$ERLANG_VERSION" && \
    ERLANG_INSTALLED=$(asdf list erlang | tr -d ' ' | tail -n1) && \
    asdf set -u erlang "$ERLANG_INSTALLED"

# Install Elixir
ARG ELIXIR_VERSION=latest
RUN . /etc/sandbox-persistent.sh && \
    if [ "$ELIXIR_VERSION" = "latest" ]; then \
      ERLANG_MAJOR=$(asdf current erlang | awk '{print $2}' | cut -d. -f1); \
      TARGET_ELIXIR=$(asdf list all elixir | grep -E "^[0-9]+\.[0-9]+\.[0-9]+-otp-${ERLANG_MAJOR}$" | tail -n1); \
    else \
      TARGET_ELIXIR="$ELIXIR_VERSION"; \
    fi && \
    asdf install elixir "$TARGET_ELIXIR" && \
    ELIXIR_INSTALLED=$(asdf list elixir | tr -d ' ' | tail -n1) && \
    asdf set -u elixir "$ELIXIR_INSTALLED" && \
    mix local.hex --force && \
    mix local.rebar --force

# Install Node.js
ARG NODEJS_VERSION=latest
RUN . /etc/sandbox-persistent.sh && \
    asdf install nodejs "$NODEJS_VERSION" && \
    NODEJS_INSTALLED=$(asdf list nodejs | tr -d ' ' | tail -n1) && \
    asdf set -u nodejs "$NODEJS_INSTALLED"

# Update npm
ARG NPM_VERSION=latest
RUN . /etc/sandbox-persistent.sh && \
    npm install -g "npm@$NPM_VERSION"

FROM elixir-docker AS agy-elixir-docker

LABEL com.docker.sandboxes.flavor="agy-docker"

USER agent

ARG AGY_CACHEBUST
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
