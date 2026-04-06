#!/bin/sh
set -e

# Fix ownership of Docker-managed named volumes (created as root:root).
if [ "$(id -u)" = "0" ]; then
    chown agent:agent /gc/.dolt-data
    # Set dolt/git config for root — needed when exec-ing into the container
    # (docker compose exec gives a root shell, not agent).
    if [ -n "$GIT_USER" ] && [ -n "$GIT_EMAIL" ]; then
        git config --global user.name "$GIT_USER"
        git config --global user.email "$GIT_EMAIL"
        dolt config --global --add user.name "$GIT_USER"
        dolt config --global --add user.email "$GIT_EMAIL"
    fi
    if [ -n "$GH_TOKEN" ]; then
        git config --global credential.helper '!f() { echo "username=x-access-token"; echo "password=$GH_TOKEN"; }; f'
    fi
    export HOME=/home/agent
    exec setpriv --reuid=1000 --regid=1000 --init-groups -- "$0" "$@"
fi

# --- Below runs as agent ---

# Re-apply git/dolt config on every start.
if [ -n "$GIT_USER" ] && [ -n "$GIT_EMAIL" ]; then
    git config --global user.name "$GIT_USER"
    git config --global user.email "$GIT_EMAIL"
    dolt config --global --add user.name "$GIT_USER"
    dolt config --global --add user.email "$GIT_EMAIL"
fi

# Use a fine-grained PAT for git auth — never written to disk.
# Single quotes so $GH_TOKEN is evaluated at runtime, not baked in at startup.
if [ -n "$GH_TOKEN" ]; then
    git config --global credential.helper '!f() { echo "username=x-access-token"; echo "password=$GH_TOKEN"; }; f'
else
    echo "WARNING: GH_TOKEN not set — git operations requiring auth will fail."
fi

# Write env vars to shell profile so all shells spawned by gc/tmux inherit them.
# (tmux isn't running at container start time, so set-environment -g isn't usable here)
{
    echo "export GH_TOKEN='${GH_TOKEN:-}'"
    echo "export GIT_USER='${GIT_USER:-}'"
    echo "export GIT_EMAIL='${GIT_EMAIL:-}'"
} > /home/agent/.env_gc
grep -qxF '[ -f ~/.env_gc ] && . ~/.env_gc' /home/agent/.bashrc || echo '[ -f ~/.env_gc ] && . ~/.env_gc' >> /home/agent/.bashrc
grep -qxF '[ -f ~/.env_gc ] && . ~/.env_gc' /home/agent/.zshrc || echo '[ -f ~/.env_gc ] && . ~/.env_gc' >> /home/agent/.zshrc

# Init city if not already initialized.
if [ ! -f /gc/city.toml ]; then
    echo "No city.toml found — run: gc init /gc"
else
    echo "Gas City workspace found at /gc."
fi

exec "$@"
