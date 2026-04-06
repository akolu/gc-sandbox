# Gas City sandbox container — builds gc and beads from source at pinned commits.
#
# Build:
#   docker compose build
#
# Bump pinned versions deliberately when upgrading.

FROM docker/sandbox-templates:claude-code

# --- Pinned versions ---
ARG GC_COMMIT=057c7338b49568cde0ba78c0e6cf291289df3094
ARG BD_REPO=gastownhall/beads
ARG BD_COMMIT=v1.0.0

USER root

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    tmux \
    curl \
    jq \
    ripgrep \
    zsh \
    gh \
    tini \
    libicu-dev \
    procps \
    lsof \
    util-linux \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Go — latest stable (apt version is too old)
RUN ARCH=$(dpkg --print-architecture) && \
    GO_VERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | sed 's/go//') && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/home/agent/go/bin:${PATH}"

# Dolt — latest stable
RUN curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash

# bd (beads) — built from pinned commit, source kept for agent reference
RUN git clone https://github.com/${BD_REPO}.git /usr/local/src/beads && \
    cd /usr/local/src/beads && \
    git checkout ${BD_COMMIT} && \
    go build -o /usr/local/bin/bd ./cmd/bd

# gc (Gas City) — built from pinned tag, source kept for agent reference
RUN git clone https://github.com/gastownhall/gascity.git /usr/local/src/gascity && \
    cd /usr/local/src/gascity && \
    git checkout ${GC_COMMIT} && \
    go build -o /usr/local/bin/gc ./cmd/gc

# Rewrite SSH git URLs to HTTPS (no SSH keys in container, auth via GH_TOKEN)
RUN git config --global url."https://github.com/".insteadOf "git@github.com:"

# Workspace dirs
RUN mkdir -p /gc /gc/.dolt-data && chown -R agent:agent /gc

ENV PATH="/gc:/home/agent/.local/bin:${PATH}"
ENV COLORTERM="truecolor"
ENV TERM="xterm-256color"

USER root

COPY --chown=agent:agent docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

WORKDIR /gc

ENTRYPOINT ["tini", "--", "/app/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
