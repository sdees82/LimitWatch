# limitWatch

`limitWatch` is a small watchOS project for viewing current `Codex` and `Claude Code` usage from an Apple Watch.

The repository contains:

- `limitWatch/LimitWatch`: the watchOS app
- `server`: a local Node.js helper server

The watch app talks to the local helper server running on your Mac over your LAN.

## Features

- `Codex` usage from local Codex session logs in `~/.codex/sessions`
- `Claude` usage from Anthropic's Claude Code usage endpoint through the helper server
- Current rate-limit windows when they are present in the source data
- On-device server configuration instead of hardcoded host values

## Quick Start

1. Start the helper server from the repository root:

```bash
cd server
cp .env.example .env
npm start
```

2. Open `limitWatch/LimitWatch/LimitWatch.xcodeproj` in Xcode.
3. Choose your own signing team if Xcode prompts for one.
4. Install the app on a paired iPhone + Apple Watch.
5. In the watch app, open the settings screen and enter your Mac's LAN IP.

## Helper Server API

The local helper serves:

```text
GET http://127.0.0.1:8787/health
GET http://127.0.0.1:8787/usage?provider=codex&startDate=2026-03-20
GET http://127.0.0.1:8787/usage?provider=claude
```

For `codex`, the app uses `startDate=YYYY-MM-DD` and the server also accepts `days=N` as a fallback query parameter.

Example response:

```json
{
  "provider": "codex",
  "windowDays": 1,
  "startDate": "2026-03-20T04:00:00.000Z",
  "endDate": "2026-03-20T19:27:11.688Z",
  "updatedAt": "2026-03-20T19:27:11.688Z",
  "sessionCount": 3,
  "totals": {
    "inputTokens": 28126,
    "cachedInputTokens": 25984,
    "outputTokens": 624,
    "reasoningOutputTokens": 138,
    "totalTokens": 28750
  },
  "rateLimits": {
    "primary": {
      "used_percent": 31,
      "window_minutes": 300,
      "resets_at": 1772833344
    },
    "secondary": {
      "used_percent": 13,
      "window_minutes": 10080,
      "resets_at": 1773317841
    },
    "plan_type": "plus"
  }
}
```

## Notes

- `server/.env` is local-only and should not be committed.
- The helper server is intended for local or LAN use only.
