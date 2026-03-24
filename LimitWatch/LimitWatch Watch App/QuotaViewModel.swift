import Combine
import Foundation

@MainActor
final class QuotaViewModel: ObservableObject {
    @Published var codexUsage: UsageResponse?
    @Published var claudeUsage: UsageResponse?
    @Published var isLoading = false
    @Published private var errorsByProvider: [UsageProvider: String] = [:]
    @Published var statusMessage: String?

    private let service: QuotaService
    var hostDescription: String { service.hostDescription }

    init(serverAddress: String = "") {
        service = QuotaService(serverAddress: serverAddress)
    }

    func updateServerAddress(_ serverAddress: String) {
        service.updateServerAddress(serverAddress)
        statusMessage = nil
    }

    func refreshIfIdle() async {
        guard !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorsByProvider = [:]
        statusMessage = nil
        defer { isLoading = false }

        await withTaskGroup(of: (UsageProvider, Result<UsageResponse, Error>).self) { group in
            for provider in UsageProvider.allCases {
                group.addTask {
                    do {
                        return (provider, .success(try await self.service.fetchUsage(provider: provider)))
                    } catch {
                        return (provider, .failure(error))
                    }
                }
            }

            for await (provider, result) in group {
                switch result {
                case .success(let usage):
                    setUsage(usage, for: provider)
                case .failure(let error):
                    errorsByProvider[provider] = error.localizedDescription
                }
            }
        }
    }

    func testConnection() async {
        isLoading = true
        errorsByProvider = [:]
        statusMessage = nil

        do {
            try await service.testConnection()
            statusMessage = "Mac server reachable"
            await withTaskGroup(of: (UsageProvider, Result<UsageResponse, Error>).self) { group in
                for provider in UsageProvider.allCases {
                    group.addTask {
                        do {
                            return (provider, .success(try await self.service.fetchUsage(provider: provider)))
                        } catch {
                            return (provider, .failure(error))
                        }
                    }
                }

                for await (provider, result) in group {
                    switch result {
                    case .success(let usage):
                        setUsage(usage, for: provider)
                    case .failure(let error):
                        errorsByProvider[provider] = error.localizedDescription
                    }
                }
            }
        } catch {
            errorsByProvider[.codex] = error.localizedDescription
        }

        isLoading = false
    }

    func usage(for provider: UsageProvider) -> UsageResponse? {
        switch provider {
        case .codex:
            return codexUsage
        case .claude:
            return claudeUsage
        }
    }

    func errorMessage(for provider: UsageProvider) -> String? {
        errorsByProvider[provider]
    }

    private func setUsage(_ usage: UsageResponse, for provider: UsageProvider) {
        switch provider {
        case .codex:
            codexUsage = usage
        case .claude:
            claudeUsage = usage
        }
    }
}
