# server

This package is the local helper server for `Limit Watch`.

Most users should start with the root [README](/Users/seandees/Desktop/project/README.md), which covers the full project setup. This file is only for server-specific details.

## Responsibilities

- read Codex usage from local session logs
- fetch Claude usage from Anthropic when configured
- normalize both providers into one response format
- expose local HTTP endpoints for the watch app

## Local Development

From the repository root:

```bash
cd server
cp .env.example .env
npm install
npm start
```

Useful commands:

```bash
npm run lint
npm test
```

## Config

The server reads configuration from `.env`.

The startup script uses Node's built-in `--env-file=.env` support, so use Node `20.6+`.

Minimum config:

```env
HOST=0.0.0.0
PORT=8787
CLAUDE_USAGE_URL=https://api.anthropic.com/api/oauth/usage
```

Optional Codex override:

```env
# CODEX_SESSIONS_DIR=/Users/yourname/.codex/sessions
```

Claude auth:

- `CLAUDE_CODE_OAUTH_TOKEN`
- `CLAUDE_CODE_AUTH_HEADER`
- `CLAUDE_CODE_COOKIE`

## Endpoints

- `GET /health`
- `GET /usage?provider=codex&startDate=YYYY-MM-DD`
- `GET /usage?provider=claude`
