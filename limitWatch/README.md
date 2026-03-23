# Limit Watch

`Limit Watch` is a watchOS app for viewing current `Codex` and `Claude Code` usage limits from your Apple Watch.

The app reads data from a local helper server running on your Mac:

- `Codex` usage is read from your local Codex session logs
- `Claude` usage is read from Anthropic's Claude Code usage endpoint through your local server

This project is now optimized for a physical iPhone + Apple Watch setup. Simulator-specific setup is not part of the main workflow.

## Project Layout

- Watch app: [`LimitWatch/`](./LimitWatch)
- Helper server: [`../server`](../server)

The watch app only needs to know your Mac's server address.
Provider credentials, including Claude auth, live on the server in its `.env`.

## Requirements

- macOS with Xcode installed
- A paired `iPhone` and `Apple Watch`
- Your `Mac`, `iPhone`, and `Apple Watch` on the same Wi-Fi network
- Node.js installed for the local helper server

## Server Setup

Start with the helper server on your Mac.

1. Open Terminal.
2. From the repository root, go to the server directory:

```bash
cd server
```

3. Create a local `.env` from `.env.example`:

```bash
cp .env.example .env
```

4. Edit `.env`.

Minimum required values:

```env
HOST=0.0.0.0
PORT=8787
CLAUDE_USAGE_URL=https://api.anthropic.com/api/oauth/usage
```

For Claude support, provide one Claude Code auth value in `.env`:

- `CLAUDE_CODE_OAUTH_TOKEN`
- or `CLAUDE_CODE_AUTH_HEADER`
- or `CLAUDE_CODE_COOKIE`

`Codex` does not require an API key. By default the server reads local Codex logs from `~/.codex/sessions`.

5. Start the server:

```bash
npm start
```

If the server starts correctly, it should listen on port `8787`.

## Find Your Mac IP

The watch app needs your Mac's local network address, not `127.0.0.1` and not `0.0.0.0`.

To get your Mac's Wi-Fi IP:

```bash
ipconfig getifaddr en0
```

Example result:

```text
192.168.2.219
```

You will enter that IP inside the watch app.

## Install The App

Use Xcode to install the iPhone container app and paired watch app.

1. Open [`LimitWatch.xcodeproj`](./LimitWatch/LimitWatch.xcodeproj) in Xcode.
2. Make sure your iPhone is paired with your Apple Watch.
3. If needed, connect the iPhone to your Mac once with a cable so Xcode can finish device setup.
4. In Xcode, select the `LimitWatch` target/project for your physical device workflow.
5. Choose your physical iPhone as the run destination with its paired Apple Watch.
6. Confirm signing is set to your Apple Developer team.
7. Enable `Developer Mode` on iPhone and Watch if Xcode prompts for it.
8. Run the project from Xcode.

Xcode installs:

- the iPhone container app on the phone
- the watch app on the paired Apple Watch

## Configure The Watch App

The watch app no longer uses a hardcoded server address.

On first launch:

1. Open `Limit Watch` on the Apple Watch.
2. Swipe to screen 3.
3. Tap `Set Server`.
4. Enter your Mac's local IP address, for example `192.168.2.219`.
5. Save.
6. Tap `Test Server`.

If the server is reachable, the app will load:

- `Codex` on the default provider screen
- `Claude` on the adjacent provider screen

## Current App Behavior

- App opens to `Codex`
- Horizontal swipe switches between `Codex` and `Claude`
- Each provider has 3 vertical screens:
  - 5 hour limit
  - weekly limit
  - detail/config screen
- The app refreshes when it loads
- The widget has been removed

## Troubleshooting

### Can't Reach The Mac Server

Check all of the following:

- the server is running with `npm start`
- `.env` uses `HOST=0.0.0.0`
- the watch app is pointed at your Mac's actual LAN IP
- your Mac, iPhone, and Watch are on the same Wi-Fi
- macOS firewall is not blocking incoming connections to Node

### `EADDRINUSE`

Port `8787` is already in use. Find and stop the existing process:

```bash
lsof -nP -iTCP:8787 -sTCP:LISTEN
kill <PID>
```

### `EADDRNOTAVAIL`

Your `.env` is trying to bind the server to an IP your Mac does not own.

Use:

```env
HOST=0.0.0.0
PORT=8787
```

Do not bind the server to your LAN IP directly.

### Claude Shows No Data

Claude support depends on valid Claude Code auth in the server `.env`.

Check that you provided one of:

- `CLAUDE_CODE_OAUTH_TOKEN`
- `CLAUDE_CODE_AUTH_HEADER`
- `CLAUDE_CODE_COOKIE`

Then restart the server.

## Notes For Contributors

Current configuration responsibilities are intentionally split:

- watch app: server host only
- server: provider auth and usage-source configuration

If you extend this project, preserve that split unless there is a strong reason to move provider credentials into a different local setup flow.

Do not commit the server's local `.env` file or Xcode build artifacts.
