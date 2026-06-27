# Muddle

Self-hosted group video calling over WebRTC, with playful AR-style
accessories. Spin up a room, share a guest link, and overlay hats, glasses,
and other props pinned to your face/body during the call. Phoenix LiveView
and [Membrane](https://membrane.stream) on top of PostgreSQL.

## Features

- **WebRTC rooms** — real-time group video calls built on the Membrane RTC
  Engine; join a call at `/r/:slug`.
- **Guest links** — invite anyone into a call without an account via
  `/g/:token` (anonymous participants).
- **Accessories** — image overlays (hats, glasses, …) that pin to a body
  keypoint live during a call.
- **Drips** — save a bundle of accessory pins as an "outfit" and apply the
  whole look in one click mid-call.
- **Room management** — create rooms at `/rooms`, with owner controls at
  `/rooms/:slug/manage`.
- **Accounts** — magic-link login by default, password optional, with
  invite-gated registration (`/users/invites`).
- **Themes** — pick a daisyUI theme; the choice persists.

## Quick start

The Membrane WebRTC stack has native dependencies. `ex_dtls` builds against
OpenSSL, so install **pkg-config** and **libssl-dev** first (on Debian/Ubuntu:
`apt-get install pkg-config libssl-dev`).

```sh
# 1. Bring up Postgres (see compose.yml)
podman compose up -d   # or: docker compose up -d

# 2. Install deps, create + migrate the dev DB, build assets
mix setup

# 3. Start the dev server
mix phx.server
```

Then open <http://localhost:4000>. Registration is invite-only by default —
mint a link from `/users/invites`, or seed an initial confirmed user:

```sh
mix run -e 'Muddle.Release.init("you@example.com", "a strong password")'
```

## Container images

CI publishes a multi-registry image on every push to `master`:

- `ghcr.io/neiam/muddle`
- `docker.io/neiam/muddle`
- `quay.io/neiam/muddle`

Tags: `latest` (default branch), `vX.Y.Z` + `X.Y` (git tags), the branch name,
and the commit SHA.

```sh
docker pull ghcr.io/neiam/muddle:latest

docker run --rm -p 4000:4000 \
  -e PHX_SERVER=true \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PHX_HOST=localhost \
  -e POSTGRES_HOST=host.containers.internal \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=muddle \
  ghcr.io/neiam/muddle:latest
```

Or set `DATABASE_URL=ecto://user:pass@host/db` instead of the discrete
`POSTGRES_*` variables. For production WebRTC, set `MUDDLE_ICE_SERVERS` with
your STUN/TURN configuration.

## Tests

```sh
mix test
mix precommit   # compile --warnings-as-errors, deps.unlock --unused, format, test
```

`mix precommit` is what CI runs and what every change should pass.
