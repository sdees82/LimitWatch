const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const http = require("node:http");
const { URL } = require("node:url");

const DEFAULT_CLAUDE_USAGE_URL = process.env.CLAUDE_USAGE_URL || "https://api.anthropic.com/api/oauth/usage";
const SUPPORTED_PROVIDERS = new Set(["codex", "claude"]);
const DEFAULT_HOST = process.env.HOST || "127.0.0.1";
const DEFAULT_PORT = process.env.PORT || 8787;

loadDefaultEnvFiles();

function loadDefaultEnvFiles() {
  const candidatePaths = [
    path.join(__dirname, ".env"),
    path.join(__dirname, "..", ".env"),
  ];

  for (const filePath of candidatePaths) {
    loadEnvFile(filePath);
  }
}

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  const lines = fs.readFileSync(filePath, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex <= 0) {
      continue;
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    if (!key || Object.prototype.hasOwnProperty.call(process.env, key)) {
      continue;
    }

    let value = trimmed.slice(separatorIndex + 1).trim();
    if (
      (value.startsWith("\"") && value.endsWith("\"")) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    process.env[key] = value;
  }
}

function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function parsePort(value) {
  if (value == null || value === "") {
    return DEFAULT_PORT;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw createError(500, `Invalid PORT value: ${value}`);
  }

  return parsed;
}

function parseHost(value) {
  if (value == null || value.trim() === "") {
    return DEFAULT_HOST;
  }

  return value.trim();
}

function parseClaudeUsageURL(value) {
  const rawValue = value || DEFAULT_CLAUDE_USAGE_URL;

  try {
    const url = new URL(rawValue);
    if (!/^https?:$/.test(url.protocol)) {
      throw new Error("unsupported protocol");
    }
    return url.toString();
  } catch {
    throw createError(500, `Invalid CLAUDE_USAGE_URL value: ${rawValue}`);
  }
}

function getConfig(env = process.env) {
  return {
    host: parseHost(env.HOST),
    port: parsePort(env.PORT),
    sessionsRoot: env.CODEX_SESSIONS_DIR || path.join(os.homedir(), ".codex", "sessions"),
    claudeUsageUrl: parseClaudeUsageURL(env.CLAUDE_USAGE_URL),
    claudeAuthHeader: env.CLAUDE_CODE_AUTH_HEADER || "",
    claudeOauthToken: env.CLAUDE_CODE_OAUTH_TOKEN || "",
    claudeCookie: env.CLAUDE_CODE_COOKIE || "",
  };
}

function listJsonlFiles(rootDir) {
  const files = [];

  function walk(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const entryPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(entryPath);
      } else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        files.push(entryPath);
      }
    }
  }

  if (fs.existsSync(rootDir)) {
    walk(rootDir);
  }

  return files.sort();
}

function safeJsonParse(line) {
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

function toFiniteNumber(value) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function emptyUsage() {
  return {
    inputTokens: 0,
    cachedInputTokens: 0,
    outputTokens: 0,
    reasoningOutputTokens: 0,
    totalTokens: 0,
  };
}

function usageGreaterThan(a, b) {
  return (a.totalTokens || 0) > (b.totalTokens || 0);
}

function normalizeUsage(raw) {
  if (!raw) {
    return emptyUsage();
  }

  return {
    inputTokens: toFiniteNumber(raw.input_tokens),
    cachedInputTokens: toFiniteNumber(raw.cached_input_tokens),
    outputTokens: toFiniteNumber(raw.output_tokens),
    reasoningOutputTokens: toFiniteNumber(raw.reasoning_output_tokens),
    totalTokens: toFiniteNumber(raw.total_tokens),
  };
}

function sumUsage(a, b) {
  return {
    inputTokens: a.inputTokens + b.inputTokens,
    cachedInputTokens: a.cachedInputTokens + b.cachedInputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
    reasoningOutputTokens: a.reasoningOutputTokens + b.reasoningOutputTokens,
    totalTokens: a.totalTokens + b.totalTokens,
  };
}

function parseSessionFile(filePath, startTimeMs) {
  const lines = fs.readFileSync(filePath, "utf8").split("\n").filter(Boolean);
  let maxUsage = emptyUsage();
  let latestTimestamp = null;
  let latestRateLimits = null;
  let hadInRangeEvent = false;

  for (const line of lines) {
    const record = safeJsonParse(line);
    if (!record || record.type !== "event_msg" || record.payload?.type !== "token_count") {
      continue;
    }

    const timestampMs = Date.parse(record.timestamp || "");
    if (!Number.isFinite(timestampMs) || timestampMs < startTimeMs) {
      continue;
    }

    hadInRangeEvent = true;
    const usage = normalizeUsage(record.payload?.info?.total_token_usage);
    if (usageGreaterThan(usage, maxUsage)) {
      maxUsage = usage;
    }

    if (!latestTimestamp || timestampMs >= latestTimestamp) {
      latestTimestamp = timestampMs;
      if (record.payload?.rate_limits) {
        latestRateLimits = record.payload.rate_limits;
      }
    }
  }

  if (!hadInRangeEvent) {
    return null;
  }

  return {
    usage: maxUsage,
    latestTimestamp,
    latestRateLimits,
  };
}

function getLatestRateLimits(files) {
  let latestRateLimits = null;
  let latestTimestamp = null;

  for (const filePath of files) {
    const lines = fs.readFileSync(filePath, "utf8").split("\n").filter(Boolean);

    for (const line of lines) {
      const record = safeJsonParse(line);
      if (!record || record.type !== "event_msg" || record.payload?.type !== "token_count") {
        continue;
      }

      if (!record.payload?.rate_limits) {
        continue;
      }

      const timestampMs = Date.parse(record.timestamp || "");
      if (!Number.isFinite(timestampMs)) {
        continue;
      }

      if (!latestTimestamp || timestampMs >= latestTimestamp) {
        latestTimestamp = timestampMs;
        latestRateLimits = record.payload.rate_limits;
      }
    }
  }

  return {
    latestRateLimits,
    latestTimestamp,
  };
}

function aggregateCodexUsage(startTimeMs, options = {}) {
  const now = options.now ?? Date.now();
  const rootDir = options.sessionsRoot ?? getConfig().sessionsRoot;
  const files = listJsonlFiles(rootDir);

  let totals = emptyUsage();
  let latestTimestamp = null;
  let sessionCount = 0;

  for (const filePath of files) {
    const session = parseSessionFile(filePath, startTimeMs);
    if (!session) {
      continue;
    }

    sessionCount += 1;
    totals = sumUsage(totals, session.usage);

    if (!latestTimestamp || (session.latestTimestamp && session.latestTimestamp >= latestTimestamp)) {
      latestTimestamp = session.latestTimestamp;
    }
  }

  const {
    latestRateLimits,
    latestTimestamp: latestRateLimitTimestamp,
  } = getLatestRateLimits(files);

  const updatedAt = [latestTimestamp, latestRateLimitTimestamp]
    .filter((value) => Number.isFinite(value))
    .reduce((max, value) => Math.max(max, value), 0);

  return {
    provider: "codex",
    windowDays: Math.max(1, Math.ceil((now - startTimeMs) / (24 * 60 * 60 * 1000))),
    startDate: new Date(startTimeMs).toISOString(),
    endDate: new Date(now).toISOString(),
    updatedAt: updatedAt ? new Date(updatedAt).toISOString() : new Date(now).toISOString(),
    sessionCount,
    totals,
    rateLimits: latestRateLimits,
  };
}

function normalizeClaudeWindow(raw, windowMinutes) {
  if (!raw) {
    return null;
  }

  return {
    used_percent: toFiniteNumber(raw.utilization),
    window_minutes: windowMinutes,
    resets_at: toUnixSeconds(raw.resets_at),
  };
}

function toUnixSeconds(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 1e12 ? Math.floor(value / 1000) : Math.floor(value);
  }

  const parsed = Date.parse(String(value || ""));
  return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : 0;
}

function startOfDayMs(now) {
  const date = new Date(now);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

function buildClaudeHeaders(config = getConfig()) {
  const authHeader = config.claudeAuthHeader;
  const oauthToken = config.claudeOauthToken;
  const cookieHeader = config.claudeCookie;
  const headers = {
    accept: "application/json",
    "anthropic-beta": "oauth-2025-04-20",
  };

  if (authHeader) {
    headers.authorization = authHeader;
  } else if (oauthToken) {
    headers.authorization = /^Bearer\s/i.test(oauthToken) ? oauthToken : `Bearer ${oauthToken}`;
  }

  if (cookieHeader) {
    headers.cookie = cookieHeader;
  }

  if (!headers.authorization && !headers.cookie) {
    throw createError(
      500,
      "Claude usage requires CLAUDE_CODE_OAUTH_TOKEN, CLAUDE_CODE_AUTH_HEADER, or CLAUDE_CODE_COOKIE"
    );
  }

  return headers;
}

async function aggregateClaudeUsage(options = {}) {
  const config = options.config ?? getConfig();
  const fetchImpl = options.fetchImpl ?? globalThis.fetch;
  const now = options.now ?? Date.now();

  if (typeof fetchImpl !== "function") {
    throw createError(500, "Node.js with global fetch support is required for Claude usage");
  }

  const response = await fetchImpl(config.claudeUsageUrl, {
    method: "GET",
    headers: buildClaudeHeaders(config),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw createError(response.status, `Claude API error ${response.status}: ${detail}`);
  }

  const payload = await response.json();

  return {
    provider: "claude",
    windowDays: null,
    startDate: new Date(startOfDayMs(now)).toISOString(),
    endDate: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
    sessionCount: 0,
    totals: emptyUsage(),
    rateLimits: {
      primary: normalizeClaudeWindow(payload.five_hour, 300) ?? undefined,
      secondary: normalizeClaudeWindow(payload.seven_day, 7 * 24 * 60) ?? undefined,
      tertiary: normalizeClaudeWindow(payload.seven_day_sonnet, 7 * 24 * 60) ?? undefined,
      extra_usage: payload.extra_usage || null,
    },
  };
}

function parseProvider(requestURL) {
  const provider = (requestURL.searchParams.get("provider") || "codex").toLowerCase();
  if (!SUPPORTED_PROVIDERS.has(provider)) {
    throw createError(400, `Unsupported provider: ${provider}`);
  }
  return provider;
}

function parseDateOnly(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }

  const timestampMs = Date.parse(`${value}T00:00:00Z`);
  return Number.isFinite(timestampMs) ? timestampMs : null;
}

function parseDays(value) {
  if (value == null || value === "") {
    return 7;
  }

  if (!/^\d+$/.test(String(value))) {
    throw createError(400, `Invalid days value: ${value}`);
  }

  const days = Number(value);
  if (!Number.isInteger(days) || days < 1 || days > 30) {
    throw createError(400, "days must be an integer between 1 and 30");
  }

  return days;
}

function parseStartTimeMs(requestURL, now = Date.now()) {
  const startDate = requestURL.searchParams.get("startDate");
  if (startDate != null) {
    const startTimeMs = parseDateOnly(startDate);
    if (startTimeMs == null) {
      throw createError(400, `Invalid startDate value: ${startDate}`);
    }
    return startTimeMs;
  }

  const days = parseDays(requestURL.searchParams.get("days"));
  return now - days * 24 * 60 * 60 * 1000;
}

function writeJson(res, statusCode, data) {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
  });
  res.end(body);
}

async function readUsage(requestURL, options = {}) {
  const provider = parseProvider(requestURL);
  if (provider === "claude") {
    return aggregateClaudeUsage(options);
  }

  return aggregateCodexUsage(parseStartTimeMs(requestURL, options.now), options);
}

async function handleUsage(requestURL, res, options = {}) {
  try {
    writeJson(res, 200, await readUsage(requestURL, options));
  } catch (error) {
    const statusCode =
      error instanceof Error && typeof error.statusCode === "number"
        ? error.statusCode
        : 500;

    writeJson(res, statusCode, {
      error: "Failed to read usage data",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}

function createApp(options = {}) {
  const config = options.config ?? getConfig();
  const runtimeOptions = {
    config,
    sessionsRoot: config.sessionsRoot,
    fetchImpl: options.fetchImpl,
    now: options.now,
  };

  return http.createServer((req, res) => {
    const requestURL = new URL(req.url || "/", `http://${req.headers.host || `${config.host}:${config.port}`}`);

    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
      });
      res.end();
      return;
    }

    if (req.method === "GET" && requestURL.pathname === "/health") {
      writeJson(res, 200, { ok: true });
      return;
    }

    if (req.method === "GET" && requestURL.pathname === "/usage") {
      void handleUsage(requestURL, res, runtimeOptions);
      return;
    }

    writeJson(res, 404, { error: "Not found" });
  });
}

function startServer(options = {}) {
  const config = options.config ?? getConfig();
  const server = createApp({ ...options, config });
  server.listen(config.port, config.host, () => {
    process.stdout.write(`Codex usage server listening on http://${config.host}:${config.port}\n`);
  });
  return server;
}

if (require.main === module) {
  startServer();
}

module.exports = {
  DEFAULT_CLAUDE_USAGE_URL,
  DEFAULT_HOST,
  DEFAULT_PORT,
  SUPPORTED_PROVIDERS,
  aggregateClaudeUsage,
  aggregateCodexUsage,
  buildClaudeHeaders,
  createApp,
  emptyUsage,
  getConfig,
  handleUsage,
  loadEnvFile,
  normalizeClaudeWindow,
  normalizeUsage,
  parseDays,
  parsePort,
  parseProvider,
  parseStartTimeMs,
  readUsage,
  safeJsonParse,
  startOfDayMs,
  startServer,
  sumUsage,
  toUnixSeconds,
};
