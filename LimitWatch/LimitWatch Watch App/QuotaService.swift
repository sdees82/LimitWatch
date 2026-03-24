import Foundation

struct ServerConfiguration {
    static let storageKey = "serverAddress"
    static let defaultPort = 8787
    static let placeholderAddress = "192.168.1.10"

    let rawValue: String

    private var trimmedValue: String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !trimmedValue.isEmpty
    }

    var displayAddress: String {
        guard isConfigured else { return "Not configured" }

        if let url = normalizedURL {
            let host = url.host ?? trimmedValue
            let port = url.port ?? Self.defaultPort
            return port == Self.defaultPort ? host : "\(host):\(port)"
        }

        return trimmedValue
    }

    var normalizedStorageValue: String {
        if let url = normalizedURL {
            let host = url.host ?? trimmedValue
            let port = url.port ?? Self.defaultPort
            return port == Self.defaultPort ? host : "\(host):\(port)"
        }

        return trimmedValue
    }

    var normalizedURL: URL? {
        guard isConfigured else { return nil }

        if let explicitURL = URL(string: trimmedValue), explicitURL.scheme != nil {
            var components = URLComponents(url: explicitURL, resolvingAgainstBaseURL: false)
            if components?.port == nil {
                components?.port = Self.defaultPort
            }
            return components?.url
        }

        let hostParts = trimmedValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard let host = hostParts.first, !host.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        components.host = String(host)
        if hostParts.count == 2, let customPort = Int(hostParts[1]) {
            components.port = customPort
        } else {
            components.port = Self.defaultPort
        }

        return components.url
    }
}

final class QuotaService {
    private var configuration: ServerConfiguration

    init(serverAddress: String) {
        configuration = ServerConfiguration(rawValue: serverAddress)
    }

    func updateServerAddress(_ serverAddress: String) {
        configuration = ServerConfiguration(rawValue: serverAddress)
    }

    private func usageURL(for provider: UsageProvider) throws -> URL {
        let baseURL = try resolvedBaseURL()
        var components = URLComponents(url: baseURL.appendingPathComponent("usage"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "provider", value: provider.rawValue)]

        if provider == .codex {
            queryItems.append(
                URLQueryItem(
                    name: "startDate",
                    value: Self.startDateFormatter.string(from: Calendar.current.startOfDay(for: Date()))
                )
            )
        }

        components.queryItems = queryItems
        return components.url!
    }

    private func healthURL() throws -> URL {
        try resolvedBaseURL().appendingPathComponent("health")
    }

    var hostDescription: String {
        configuration.displayAddress
    }

    func fetchUsage(provider: UsageProvider) async throws -> UsageResponse {
        var request = URLRequest(url: try usageURL(for: provider))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw NSError(domain: "QuotaService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "API error \(http.statusCode): \(body)"
            ])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(UsageServerResponse.self, from: data)
        return UsageResponse(
            provider: payload.provider,
            startDate: payload.startDate,
            endDate: payload.endDate,
            inputTokens: payload.totals.inputTokens,
            cachedInputTokens: payload.totals.cachedInputTokens,
            outputTokens: payload.totals.outputTokens,
            reasoningOutputTokens: payload.totals.reasoningOutputTokens,
            requestCount: payload.sessionCount,
            updatedAt: payload.updatedAt,
            primaryRateLimit: payload.rateLimits?.primary,
            secondaryRateLimit: payload.rateLimits?.secondary,
            tertiaryRateLimit: payload.rateLimits?.tertiary,
            planType: payload.rateLimits?.planType,
            extraUsageEnabled: payload.rateLimits?.extraUsage?.isEnabled
        )
    }

    func testConnection() async throws {
        var request = URLRequest(url: try healthURL())
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                throw NSError(
                    domain: "QuotaService",
                    code: error.errorCode,
                    userInfo: [NSLocalizedDescriptionKey: "No network connection. Make sure the watch and Mac are on the same Wi-Fi."]
                )
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .timedOut:
                throw NSError(
                    domain: "QuotaService",
                    code: error.errorCode,
                    userInfo: [NSLocalizedDescriptionKey: "Can't reach the Mac server at \(hostDescription). Check that `npm start` is running, your Mac IP is correct, and firewall access is allowed."]
                )
            default:
                throw error
            }
        }
    }

    private func resolvedBaseURL() throws -> URL {
        guard configuration.isConfigured else {
            throw NSError(
                domain: "QuotaService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Set your Mac server address first. Use the third screen to enter your Mac's local IP."]
            )
        }

        guard let url = configuration.normalizedURL else {
            throw NSError(
                domain: "QuotaService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "The Mac server address is invalid. Enter an IP like 192.168.1.10 or host:port."]
            )
        }

        return url
    }

    private static let startDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
