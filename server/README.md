# server

Local helper server for `Limit Watch`.

This server exposes usage data on your Mac for the watch app to read over your local network.

It supports:

- `Codex` usage from local Codex session logs
- `Claude` usage from Anthropic's Claude Code usage endpoint

The server is intended for local or LAN use only.

## Requirements

- Node.js
- A Mac on the same Wi-Fi network as your iPhone and Apple Watch

## Setup

From the repository root:

```bash
cd server
cp .env.example .env
```

Edit `.env` with at least:

```env
HOST=0.0.0.0
PORT=8787
CLAUDE_USAGE_URL=https://api.anthropic.com/api/oauth/usage
```

## Codex Setup

No API key is required for Codex.

By default, the server reads local Codex session logs from:

```text
~/.codex/sessions
```

If needed, override that path in `.env`:

```env
# CODEX_SESSIONS_DIR=/Users/yourname/.codex/sessions
```

## Claude Setup

Claude support requires Claude Code auth in `.env`.

Provide one of:

- `CLAUDE_CODE_OAUTH_TOKEN`
- `CLAUDE_CODE_AUTH_HEADER`
- `CLAUDE_CODE_COOKIE`

Example:

```env
CLAUDE_CODE_OAUTH_TOKEN=your-token-here
```

If Claude auth is missing, the server can still run in Codex-only mode.

## Run The Server

Start it with:

```bash
npm start
```

The server binds to:

```text
http://0.0.0.0:8787
```

Clients should connect using your Mac's actual LAN IP, for example:

```text
http://192.168.2.219:8787
```

## Endpoints

### `GET /health`

Basic health check.

### `GET /usage?provider=codex&startDate=YYYY-MM-DD`

Returns Codex usage and limit information.

The watch app sends `startDate` for a day-based rolling window. The server also accepts `days=N` as a fallback.

### `GET /usage?provider=claude`

Returns Claude usage and limit information from the Claude Code usage API.

## Find Your Mac IP

To find the address the watch app should use:

```bash
ipconfig getifaddr en0
```

Use that IP in the watch app's `Set Server` screen.

## Troubleshooting

### `EADDRINUSE`

Port `8787` is already in use:

```bash
lsof -nP -iTCP:8787 -sTCP:LISTEN
kill <PID>
```

### `EADDRNOTAVAIL`

You are trying to bind the server to an IP your Mac does not own.

Use this in `.env`:

```env
HOST=0.0.0.0
PORT=8787
```

Do not bind the server directly to your LAN IP.

### Claude Is Not Loading

Check:

- `.env` contains valid Claude Code auth
- the server was restarted after editing `.env`
- the watch app is pointing to the correct Mac IP

## Security

- Keep this server on your local network
- Do not expose it publicly to the internet
- Do not commit real credentials or the local `.env` file
