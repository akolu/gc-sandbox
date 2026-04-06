# gc-sandbox

Sandboxed [Gas City](https://github.com/gastownhall/gascity) environment running in Docker. Gas City and beads are built from source at pinned commits for full control over upgrades.

## Usage

```bash
# Copy and fill in your values
cp .env.example .env

# Build (compiles Go from source — takes a few minutes)
docker compose build

# Start
docker compose up -d
docker compose exec gascity zsh
```

Inside the container:

```bash
gc init /gc
gc start
gc session at mayor
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
| Go | Floating (latest stable) | Stable release cadence, want security patches automatically |
| Dolt | Floating (latest stable) | Stable release cadence, want security patches automatically |

To upgrade `gc` or `bd`, bump the args in `Dockerfile` and run `docker compose build --no-cache`.

## Volume Layout

| Mount | What |
|---|---|
| `${FOLDER}` → `/gc` | Your gc folder (city config, rigs, etc.) |
| `./agent-config` → `/home/agent/.claude` | Claude credentials and settings — persists across `docker compose down -v`, not committed |
| `agent-home` (named volume) | Claude binary, Go/npm tools — survives `docker compose down` |
| `dolt-data` (named volume) | Dolt data — named volume avoids VirtioFS fsync issues on macOS |

## Resetting State

Claude Code conversation history lives in `agent-home`. GC session references live in `gc/.gc/`. These must stay in sync — losing one without the other causes GC to reference conversations that no longer exist.

```bash
# Partial restart (keeps all state)
docker compose down && docker compose up -d

# Full clean reset — wipe both together or not at all
docker compose down -v && rm -rf /path/to/your/gc/.gc
```

## Security Model

The container drops all Linux capabilities except those needed for the root→agent privilege drop at startup (`CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE`, `FOWNER`). These remain in the capability set after the drop — a compromised agent process retains write access to the mounted `FOLDER`.

| Attack surface | Mitigation |
|---|---|
| Host filesystem | Only `FOLDER` and Dolt volume mounted — host is otherwise inaccessible |
| GitHub credentials | Fine-grained PAT scoped to specific repos; written to `agent-home` volume with mode 600 |
| Container escape | `no-new-privileges`, all caps dropped except startup set |
| Outbound network | Unrestricted — accepted risk for a local dev sandbox |
