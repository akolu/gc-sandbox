#!/bin/sh
set -e

# Fix ownership of Docker-managed named volumes (created as root:root).
# Note: /gc itself is a bind-mount from FOLDER — agent (uid 1000) must own it on the host
# or gc operations will fail with permission denied.
if [ "$(id -u)" = "0" ]; then
    chown agent:agent /gc/.dolt-data
    export HOME=/home/agent
    exec setpriv --reuid=1000 --regid=1000 --init-groups --inh-caps=-all --ambient-caps=-all --bounding-set=-all -- /app/docker-entrypoint.sh "$@"
fi

# --- Below runs as agent ---

# Apply git/dolt config on every start (agent-home named volume persists across restarts).
if [ -n "$GIT_USER" ] && [ -n "$GIT_EMAIL" ]; then
    git config --global user.name "$GIT_USER"
    git config --global user.email "$GIT_EMAIL"
    dolt config --global --set user.name "$GIT_USER"
    dolt config --global --set user.email "$GIT_EMAIL"
fi

# Rewrite SSH git URLs to HTTPS — no SSH keys in container, auth via GH_TOKEN.
git config --global url."https://github.com/".insteadOf "git@github.com:"

# Use a fine-grained PAT for git auth.
# Single quotes so $GH_TOKEN is evaluated at runtime by the credential helper, not here.
if [ -n "$GH_TOKEN" ]; then
    git config --global credential.helper '!f() { echo "username=x-access-token"; echo "password=$GH_TOKEN"; }; f'
else
    echo "ERROR: GH_TOKEN not set." && exit 1
fi

# Write env vars to shell profile so all shells spawned by gc/tmux inherit them.
# (tmux isn't running at container start time, so set-environment -g isn't usable here)
# GH_TOKEN lands on the agent-home volume — restricted to owner only.
{
    printf 'export GH_TOKEN=%s\n' "$(printf '%s' "${GH_TOKEN:-}" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
    printf 'export GIT_USER=%s\n' "$(printf '%s' "${GIT_USER:-}" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
    printf 'export GIT_EMAIL=%s\n' "$(printf '%s' "${GIT_EMAIL:-}" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
} > /home/agent/.env_gc.tmp
chmod 600 /home/agent/.env_gc.tmp
mv /home/agent/.env_gc.tmp /home/agent/.env_gc
touch /home/agent/.bashrc /home/agent/.zshrc
grep -qxF '[ -f ~/.env_gc ] && . ~/.env_gc' /home/agent/.bashrc || echo '[ -f ~/.env_gc ] && . ~/.env_gc' >> /home/agent/.bashrc
grep -qxF '[ -f ~/.env_gc ] && . ~/.env_gc' /home/agent/.zshrc || echo '[ -f ~/.env_gc ] && . ~/.env_gc' >> /home/agent/.zshrc

# Init city if not already initialized.
if [ ! -f /gc/city.toml ]; then
    echo "No city.toml found — run: gc init /gc"
else
    echo "Gas City workspace found at /gc."
fi

exec "$@"
