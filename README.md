# gc-sandbox

Sandboxed [Gas City](https://github.com/gastownhall/gascity) environment running in Docker. Refer to the Gas City repo for usage, commands, and configuration. Gas City and beads are built from source at pinned commits for full control over upgrades.

## Usage

```bash
# Copy and fill in your values
cp .env.example .env

# Build (compiles Go from source — takes a few minutes)
docker compose build

# Start
docker compose up -d
docker compose exec --user agent gascity zsh
```

Inside the container:

```bash
gc init /gc
gc start
gc session attach mayor
```

## Configuration

| Variable | Description |
|---|---|
| `FOLDER` | Path to your local gc folder, mounted at `/gc` inside the container |
| `GIT_USER` | Your git display name |
| `GIT_EMAIL` | Your git email |
| `GH_TOKEN` | Fine-grained GitHub PAT scoped to the repos GC needs |

Set these in `.env` (see `.env.example`).

## Versions

| Dep | Strategy | Why |
|---|---|---|
| Gas City (`gc`) | Pinned | Fast-moving project — explicit opt-in to updates |
| beads (`bd`) | Pinned | Same — upgrade deliberately when ready |
| Go | Floating (latest stable) | Stable release cadence, want security patches automatically. SHA256 verified against go.dev at build time (same-origin — protects against corruption, not a compromised origin) |
| Dolt | Pinned | Same — upgrade deliberately when ready |

To upgrade `gc` or `bd`, bump the args in `Dockerfile` and run `docker compose build --no-cache`.

## Volume Layout

| Mount | What |
|---|---|
| `${FOLDER}` → `/gc` | Your gc folder (city config, rigs, etc.) |
| `./agent-config` → `/home/agent/.claude` | Claude credentials and settings — bind-mounted from host, persists across `docker compose down -v`, not committed |
| `agent-home` (named volume) | Claude binary, Go/npm tools, git config, shell profiles — survives `docker compose down` |
| `dolt-data` (named volume) | Dolt data — named volume avoids VirtioFS fsync issues on macOS. Mounted at `/gc/.dolt-data`, shadowing that path on the host `FOLDER` — don't use `$FOLDER/.dolt-data` directly |

## Resetting State

Claude Code conversation history lives in `agent-config/` (the bind mount). GC session references live in `gc/.gc/`. These must stay in sync — losing one without the other causes GC to reference conversations that no longer exist.

```bash
# Partial restart (keeps all state)
docker compose down && docker compose up -d

# Full clean reset — wipe both together or not at all (substitute your FOLDER path)
docker compose down -v && rm -rf "${FOLDER}/.gc"
```

## Security Model

The container adds `CHOWN`, `SETUID`, and `SETGID` for the root→agent privilege drop at startup. The entrypoint strips all inherited and ambient capabilities before exec-ing as agent. `no-new-privileges` prevents re-escalation via suid binaries.

| Attack surface | Mitigation |
|---|---|
| Host filesystem | Only `FOLDER` (read-write) and Dolt volume mounted — host is otherwise inaccessible |
| GitHub credentials | Fine-grained PAT scoped to specific repos; present in process environment for the container lifetime — readable via `docker inspect` by anyone with Docker socket access on the host |
| Anthropic credentials | OAuth token in `agent-config/` is bind-mounted into the container — accessible to any code the agent runs |
| Container escape | `no-new-privileges` (blocks suid escalation); root startup phase holds `CHOWN/SETUID/SETGID` only until entrypoint privilege drop, after which agent process has no inherited or ambient capabilities |
| Outbound network | Unrestricted — accepted risk for a local dev sandbox |
