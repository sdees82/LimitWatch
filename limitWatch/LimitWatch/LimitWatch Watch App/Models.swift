import Foundation

enum UsageProvider: String, CaseIterable, Identifiable, Decodable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }
}

struct UsageResponse {
    let provider: UsageProvider
    let startDate: Date
    let endDate: Date
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let requestCount: Int
    let updatedAt: Date
    let primaryRateLimit: RateLimitWindow?
    let secondaryRateLimit: RateLimitWindow?
    let tertiaryRateLimit: RateLimitWindow?
    let planType: String?
    let extraUsageEnabled: Bool?
}

struct UsageServerResponse: Decodable {
    let provider: UsageProvider
    let windowDays: Int?
    let startDate: Date
    let endDate: Date
    let updatedAt: Date
    let sessionCount: Int
    let totals: UsageTotals
    let rateLimits: RateLimits?
}

struct UsageTotals: Decodable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int
}

struct RateLimits: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let tertiary: RateLimitWindow?
    let planType: String?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case tertiary
        case planType = "plan_type"
        case extraUsage = "extra_usage"
    }
}

struct ExtraUsage: Decodable {
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
    }
}

struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    var resetDate: Date {
        Date(timeIntervalSince1970: resetsAt)
    }

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }
}

extension UsageResponse {
    static let preview = UsageResponse(
        provider: .codex,
        startDate: Date(timeIntervalSince1970: 1_742_433_600),
        endDate: Date(timeIntervalSince1970: 1_742_520_000),
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        requestCount: 0,
        updatedAt: Date(timeIntervalSince1970: 1_742_520_000),
        primaryRateLimit: nil,
        secondaryRateLimit: nil,
        tertiaryRateLimit: nil,
        planType: "plus",
        extraUsageEnabled: nil
    )

    static let claudePreview = UsageResponse(
        provider: .claude,
        startDate: Date(timeIntervalSince1970: 1_742_433_600),
        endDate: Date(timeIntervalSince1970: 1_742_520_000),
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        requestCount: 0,
        updatedAt: Date(timeIntervalSince1970: 1_742_520_000),
        primaryRateLimit: RateLimitWindow(usedPercent: 37, windowMinutes: 300, resetsAt: Date().addingTimeInterval(6_300).timeIntervalSince1970),
        secondaryRateLimit: RateLimitWindow(usedPercent: 26, windowMinutes: 10_080, resetsAt: Date().addingTimeInterval(280_800).timeIntervalSince1970),
        tertiaryRateLimit: RateLimitWindow(usedPercent: 1, windowMinutes: 10_080, resetsAt: Date().addingTimeInterval(280_800).timeIntervalSince1970),
        planType: nil,
        extraUsageEnabled: false
    )
}
