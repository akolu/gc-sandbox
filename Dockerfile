# Gas City sandbox container — builds gc and beads from source at pinned commits.
#
# Build:
#   docker compose build
#
# Bump pinned versions deliberately when upgrading.

# Pinned 2026-04-06 — bump digest when updating the base image
FROM docker/sandbox-templates:claude-code@sha256:c35ac0d4ba1d680466b0d267ce732d758819a09db3a1a331207f62efa2e593d0

# --- Pinned versions ---
ARG GC_REPO=gastownhall/gascity
ARG GC_COMMIT=057c7338b49568cde0ba78c0e6cf291289df3094
ARG BD_REPO=gastownhall/beads
ARG BD_COMMIT=72170267e00a96ec888f68a3279ddf0173b7adc7
ARG DOLT_VERSION=v1.85.0
ARG DOLT_INSTALL_SHA256=4aa97f7349632e845eb3891667b73e7eea5e12999c92f73d6144d1e6fb346697

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

# Go — latest stable (apt version is too old), tarball verified against go.dev/dl JSON API
RUN ARCH=$(dpkg --print-architecture) && \
    RELEASE=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0]') && \
    GO_VERSION=$(echo "$RELEASE" | jq -r '.version' | sed 's/go//') && \
    EXPECTED_SHA=$(echo "$RELEASE" | jq -r --arg arch "$ARCH" '.files[] | select(.os=="linux" and .arch==$arch) | .sha256') && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz && \
    echo "${EXPECTED_SHA}  /tmp/go.tar.gz" | sha256sum -c && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:/home/agent/go/bin:${PATH}"

# Dolt — pinned version, install script verified by SHA256
RUN curl -fsSL "https://github.com/dolthub/dolt/releases/download/${DOLT_VERSION}/install.sh" -o /tmp/dolt-install.sh && \
    echo "${DOLT_INSTALL_SHA256}  /tmp/dolt-install.sh" | sha256sum -c && \
    bash /tmp/dolt-install.sh && \
    rm /tmp/dolt-install.sh

# bd (beads) — built from pinned commit, source kept for agent reference
RUN git clone https://github.com/${BD_REPO}.git /usr/local/src/beads && \
    cd /usr/local/src/beads && \
    git checkout ${BD_COMMIT} && \
    go build -o /usr/local/bin/bd ./cmd/bd

# gc (Gas City) — built from pinned commit, source kept for agent reference
RUN git clone https://github.com/${GC_REPO}.git /usr/local/src/gascity && \
    cd /usr/local/src/gascity && \
    git checkout ${GC_COMMIT} && \
    go build -o /usr/local/bin/gc ./cmd/gc

# Workspace dirs
RUN mkdir -p /gc /gc/.dolt-data

ENV PATH="/home/agent/.local/bin:${PATH}"
ENV COLORTERM="truecolor"
ENV TERM="xterm-256color"

COPY --chown=agent:agent docker-entrypoint.sh /app/docker-entrypoint.sh

WORKDIR /gc

ENTRYPOINT ["tini", "--", "/app/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]  # keep-alive for docker compose exec usage
