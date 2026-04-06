# Gas City sandbox container — builds gc and beads from source at pinned commits.
#
# Build:
#   docker compose build
#
# Bump pinned versions deliberately when upgrading.

FROM docker/sandbox-templates:claude-code@sha256:c35ac0d4ba1d680466b0d267ce732d758819a09db3a1a331207f62efa2e593d0

# --- Pinned versions ---
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

# Go — latest stable (apt version is too old)
RUN ARCH=$(dpkg --print-architecture) && \
    GO_VERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | sed 's/go//') && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
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
