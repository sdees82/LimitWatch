const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  DEFAULT_CLAUDE_USAGE_URL,
  aggregateClaudeUsage,
  aggregateCodexUsage,
  buildClaudeHeaders,
  getConfig,
  parseDays,
  parsePort,
  parseProvider,
  parseStartTimeMs,
} = require("./server");

function makeURL(pathname) {
  return new URL(pathname, "http://127.0.0.1:8787");
}

test("getConfig applies defaults and validates values", () => {
  const config = getConfig({});
  assert.equal(config.port, 8787);
  assert.equal(config.host, "127.0.0.1");
  assert.equal(config.claudeUsageUrl, DEFAULT_CLAUDE_USAGE_URL);
  assert.match(config.sessionsRoot, /\.codex[/\\]sessions$/);
});

test("parsePort rejects invalid values", () => {
  assert.throws(() => parsePort("0"), /Invalid PORT value/);
  assert.throws(() => parsePort("99999"), /Invalid PORT value/);
  assert.equal(parsePort("8787"), 8787);
});

test("parseDays validates range and format", () => {
  assert.equal(parseDays(undefined), 7);
  assert.equal(parseDays("14"), 14);
  assert.throws(() => parseDays("abc"), /Invalid days value/);
  assert.throws(() => parseDays("31"), /between 1 and 30/);
});

test("parseProvider defaults to codex and rejects unsupported providers", () => {
  assert.equal(parseProvider(makeURL("/usage")), "codex");
  assert.equal(parseProvider(makeURL("/usage?provider=claude")), "claude");
  assert.throws(() => parseProvider(makeURL("/usage?provider=openai")), /Unsupported provider/);
});

test("parseStartTimeMs accepts strict startDate and rejects invalid input", () => {
  const timestamp = parseStartTimeMs(makeURL("/usage?startDate=2026-03-20"));
  assert.equal(timestamp, Date.parse("2026-03-20T00:00:00Z"));

  const now = Date.parse("2026-03-20T12:00:00Z");
  assert.equal(parseStartTimeMs(makeURL("/usage?days=2"), now), now - 2 * 24 * 60 * 60 * 1000);

  assert.throws(() => parseStartTimeMs(makeURL("/usage?startDate=2026/03/20")), /Invalid startDate/);
});

test("buildClaudeHeaders prefers explicit auth header and rejects missing auth", () => {
  const headers = buildClaudeHeaders({
    host: "127.0.0.1",
    port: 8787,
    sessionsRoot: "/tmp",
    claudeUsageUrl: DEFAULT_CLAUDE_USAGE_URL,
    claudeAuthHeader: "Bearer custom",
    claudeOauthToken: "oauth-token",
    claudeCookie: "session=abc",
  });

  assert.equal(headers.authorization, "Bearer custom");
  assert.equal(headers.cookie, "session=abc");

  assert.throws(
    () =>
      buildClaudeHeaders({
        host: "127.0.0.1",
        port: 8787,
        sessionsRoot: "/tmp",
        claudeUsageUrl: DEFAULT_CLAUDE_USAGE_URL,
        claudeAuthHeader: "",
        claudeOauthToken: "",
        claudeCookie: "",
      }),
    /Claude usage requires/
  );
});

test("aggregateClaudeUsage normalizes remote payload", async () => {
  const now = Date.parse("2026-03-20T12:34:56Z");
  const result = await aggregateClaudeUsage({
    now,
    config: {
      host: "127.0.0.1",
      port: 8787,
      sessionsRoot: "/tmp",
      claudeUsageUrl: DEFAULT_CLAUDE_USAGE_URL,
      claudeAuthHeader: "",
      claudeOauthToken: "token-123",
      claudeCookie: "",
    },
    fetchImpl: async (url, init) => {
      assert.equal(url, DEFAULT_CLAUDE_USAGE_URL);
      assert.equal(init?.method, "GET");
      assert.equal(init?.headers.authorization, "Bearer token-123");
      return {
        ok: true,
        async json() {
          return {
            five_hour: { utilization: 25, resets_at: "2026-03-20T15:00:00Z" },
            seven_day: { utilization: 40, resets_at: "2026-03-27T12:00:00Z" },
            seven_day_sonnet: { utilization: 10, resets_at: "2026-03-27T18:00:00Z" },
            extra_usage: { is_enabled: true },
          };
        },
      };
    },
  });

  assert.equal(result.provider, "claude");
  assert.equal(result.sessionCount, 0);
  assert.equal(result.rateLimits?.primary?.used_percent, 25);
  assert.equal(result.rateLimits?.secondary?.window_minutes, 10080);
  assert.deepEqual(result.rateLimits?.extra_usage, { is_enabled: true });
});

test("aggregateCodexUsage aggregates max session totals and latest rate limits", () => {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "limitwatch-server-test-"));

  try {
    const sessionADir = path.join(rootDir, "session-a");
    const sessionBDir = path.join(rootDir, "session-b");
    fs.mkdirSync(sessionADir, { recursive: true });
    fs.mkdirSync(sessionBDir, { recursive: true });

    fs.writeFileSync(
      path.join(sessionADir, "events.jsonl"),
      [
        JSON.stringify({
          timestamp: "2026-03-20T09:00:00Z",
          type: "event_msg",
          payload: {
            type: "token_count",
            info: {
              total_token_usage: {
                input_tokens: 10,
                cached_input_tokens: 5,
                output_tokens: 2,
                reasoning_output_tokens: 1,
                total_tokens: 12,
              },
            },
            rate_limits: { primary: { used_percent: 20 } },
          },
        }),
        JSON.stringify({
          timestamp: "2026-03-20T10:00:00Z",
          type: "event_msg",
          payload: {
            type: "token_count",
            info: {
              total_token_usage: {
                input_tokens: 30,
                cached_input_tokens: 10,
                output_tokens: 4,
                reasoning_output_tokens: 2,
                total_tokens: 36,
              },
            },
            rate_limits: { primary: { used_percent: 40 } },
          },
        }),
      ].join("\n")
    );

    fs.writeFileSync(
      path.join(sessionBDir, "events.jsonl"),
      [
        JSON.stringify({
          timestamp: "2026-03-20T11:00:00Z",
          type: "event_msg",
          payload: {
            type: "token_count",
            info: {
              total_token_usage: {
                input_tokens: 5,
                cached_input_tokens: 0,
                output_tokens: 1,
                reasoning_output_tokens: 0,
                total_tokens: 6,
              },
            },
            rate_limits: { secondary: { used_percent: 15 } },
          },
        }),
      ].join("\n")
    );

    const result = aggregateCodexUsage(Date.parse("2026-03-20T00:00:00Z"), {
      now: Date.parse("2026-03-20T12:00:00Z"),
      sessionsRoot: rootDir,
    });

    assert.equal(result.provider, "codex");
    assert.equal(result.sessionCount, 2);
    assert.deepEqual(result.totals, {
      inputTokens: 35,
      cachedInputTokens: 10,
      outputTokens: 5,
      reasoningOutputTokens: 2,
      totalTokens: 42,
    });
    assert.deepEqual(result.rateLimits, { secondary: { used_percent: 15 } });
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
});
