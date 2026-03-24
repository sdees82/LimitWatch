import Foundation
import SwiftUI

private enum WatchPalette {
    static let background = Color.black
    static let divider = Color.white.opacity(0.14)
    static let secondaryText = Color(red: 0.58, green: 0.58, blue: 0.62)
    static let ringTrack = Color(red: 0.18, green: 0.18, blue: 0.20)
    static let appGreen = Color(red: 0.24, green: 0.86, blue: 0.47)
    static let warningYellow = Color(red: 0.98, green: 0.78, blue: 0.25)
    static let dangerRed = Color(red: 0.98, green: 0.27, blue: 0.23)
    static let claudeAccent = Color(red: 0.97, green: 0.47, blue: 0.22)
}

struct ContentView: View {
    @StateObject private var vm = QuotaViewModel()
    @AppStorage(ServerConfiguration.storageKey) private var serverAddress = ""

    var body: some View {
        TabView {
            ProviderDashboard(
                provider: .codex,
                usage: vm.usage(for: .codex),
                isLoading: vm.isLoading,
                errorMessage: vm.errorMessage(for: .codex),
                statusMessage: vm.statusMessage,
                serverAddress: serverAddress,
                hostDescription: vm.hostDescription
            )
            .tag(0)

            ProviderDashboard(
                provider: .claude,
                usage: vm.usage(for: .claude),
                isLoading: vm.isLoading,
                errorMessage: vm.errorMessage(for: .claude),
                statusMessage: nil,
                serverAddress: serverAddress,
                hostDescription: vm.hostDescription
            )
            .tag(1)

            SettingsScreen(
                serverAddress: $serverAddress,
                isLoading: vm.isLoading,
                statusMessage: vm.statusMessage,
                hostDescription: vm.hostDescription,
                errorMessage: vm.errorMessage(for: .codex),
                onTestConnection: { Task { await vm.testConnection() } }
            )
            .tag(2)
        }
        .background(WatchPalette.background)
        .onChange(of: serverAddress, initial: true) { _, newValue in
            vm.updateServerAddress(newValue)
            guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { await vm.refreshIfIdle() }
        }
        .task {
            vm.updateServerAddress(serverAddress)
            await vm.refresh()
        }
    }
}

private struct ProviderDashboard: View {
    let provider: UsageProvider
    let usage: UsageResponse?
    let isLoading: Bool
    let errorMessage: String?
    let statusMessage: String?
    let serverAddress: String
    let hostDescription: String

    var body: some View {
        ProviderSummaryScreen(
            provider: provider,
            dashboardData: makeDashboardData(),
            usage: usage,
            isLoading: isLoading,
            errorMessage: errorMessage,
            statusMessage: statusMessage,
            serverAddress: serverAddress,
            hostDescription: hostDescription
        )
    }

    private func makeDashboardData(now: Date = Date()) -> LimitDashboardData {
        LimitDashboardData(
            fiveHour: LimitDisplayData(
                title: "5 Hour Limit",
                progress: usage?.primaryRateLimit?.remainingFraction ?? 0,
                percentageText: usage?.primaryRateLimit?.remainingPercentText ?? "--%",
                detailText: usage?.primaryRateLimit?.timeLeftText(now: now) ?? "Waiting for data"
            ),
            weekly: LimitDisplayData(
                title: "Weekly Limit",
                progress: usage?.secondaryRateLimit?.remainingFraction ?? 0,
                percentageText: usage?.secondaryRateLimit?.remainingPercentText ?? "--%",
                detailText: usage?.secondaryRateLimit?.weeklyResetText(now: now) ?? "Waiting for data"
            )
        )
    }
}

struct ProviderSummaryScreen: View {
    let provider: UsageProvider
    let dashboardData: LimitDashboardData
    let usage: UsageResponse?
    let isLoading: Bool
    let errorMessage: String?
    let statusMessage: String?
    let serverAddress: String
    let hostDescription: String

    private let horizontalPadding: CGFloat = 14
    private let topPadding: CGFloat = 4
    private let bottomPadding: CGFloat = 6

    var body: some View {
        ZStack {
            WatchPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HeaderView(provider: provider)
                    divider
                    LimitRingCard(data: dashboardData.fiveHour)
                    divider
                    LimitRingCard(data: dashboardData.weekly)

                    if shouldShowFooter {
                        divider
                    }

                    if isLoading {
                        Text("Refreshing...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchPalette.secondaryText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let planType = usage?.planType {
                        Text("Plan: \(planType.capitalized)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchPalette.secondaryText)
                    }

                    if let statusMessage, provider == .codex {
                        Text(statusMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchPalette.appGreen)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
        }
    }

    private var shouldShowFooter: Bool {
        isLoading || errorMessage != nil || usage?.planType != nil || (statusMessage != nil && provider == .codex)
    }

    private var divider: some View {
        Rectangle()
            .fill(WatchPalette.divider)
            .frame(height: 1)
    }
}

struct HeaderView: View {
    let provider: UsageProvider

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Limit Watch")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(provider.displayName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(providerAccent)
            }

            Spacer(minLength: 0)
        }
    }

    private var providerAccent: Color {
        switch provider {
        case .codex:
            return WatchPalette.appGreen
        case .claude:
            return WatchPalette.claudeAccent
        }
    }
}

struct LimitRingCard: View {
    let data: LimitDisplayData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(data.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(data.statusColor)

            HStack {
                Spacer(minLength: 0)
                CircularProgressRing(
                    progress: data.progress,
                    progressColor: data.statusColor,
                    percentageText: data.percentageText,
                    detailText: data.detailText
                )
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CircularProgressRing: View {
    let progress: Double
    let progressColor: Color
    let percentageText: String
    let detailText: String

    private let ringSize: CGFloat = 102
    private let strokeWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(WatchPalette.ringTrack, lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(percentageText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(detailText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(width: 64)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: ringSize, height: ringSize)
    }
}

struct SettingsScreen: View {
    @Binding var serverAddress: String
    let isLoading: Bool
    let statusMessage: String?
    let hostDescription: String
    let errorMessage: String?
    let onTestConnection: () -> Void

    private let horizontalPadding: CGFloat = 14
    private let topPadding: CGFloat = 8
    private let bottomPadding: CGFloat = 10

    var body: some View {
        ZStack {
            WatchPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    detailRow(title: "Mac Server", value: hostDescription)

                    Text("Enter your Mac's local IP. Port 8787 is used by default.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(WatchPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(ServerConfiguration.placeholderAddress, text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchPalette.appGreen)
                    } else if isLoading {
                        Text("Refreshing...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchPalette.secondaryText)
                    }

                    Button("Test Server", action: onTestConnection)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(WatchPalette.appGreen)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WatchPalette.secondaryText)

            Rectangle()
                .fill(WatchPalette.divider)
                .frame(height: 1)

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

struct LimitDashboardData {
    let fiveHour: LimitDisplayData
    let weekly: LimitDisplayData

    static let mock = LimitDashboardData(
        fiveHour: LimitDisplayData(
            title: "5 Hour Limit",
            progress: 0.64,
            percentageText: "64%",
            detailText: "2hrs 10m Left"
        ),
        weekly: LimitDisplayData(
            title: "Weekly Limit",
            progress: 0.83,
            percentageText: "83%",
            detailText: "Resets in 3d 5h"
        )
    )
}

struct LimitDisplayData {
    let title: String
    let progress: Double
    let percentageText: String
    let detailText: String

    var statusColor: Color {
        let remainingPercent = progress * 100

        if remainingPercent >= 70 {
            return WatchPalette.appGreen
        }
        if remainingPercent >= 21 {
            return WatchPalette.warningYellow
        }
        return WatchPalette.dangerRed
    }
}

private extension RateLimitWindow {
    var remainingFraction: Double {
        remainingPercent / 100
    }

    var remainingPercentText: String {
        String(format: "%.0f%%", remainingPercent)
    }

    func timeLeftText(now: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: now, to: resetDate)
        let hours = max(components.hour ?? 0, 0)
        let minutes = max(components.minute ?? 0, 0)

        if hours > 0 {
            return "\(hours)\(hours == 1 ? "hr" : "hrs") \(minutes)m Left"
        }
        if minutes > 0 {
            return "\(minutes)m Left"
        }
        return "Resetting now"
    }

    func weeklyResetText(now: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .hour], from: now, to: resetDate)
        let days = max(components.day ?? 0, 0)
        let hours = max(components.hour ?? 0, 0)

        if days > 0 {
            return "Resets in \(days)d \(hours)h"
        }
        if hours > 0 {
            return "Resets in \(hours)h"
        }
        return "Resetting soon"
    }
}

#Preview("Codex Dashboard") {
    ProviderDashboard(
        provider: .codex,
        usage: .preview,
        isLoading: false,
        errorMessage: nil,
        statusMessage: nil,
        serverAddress: "192.168.1.10",
        hostDescription: "192.168.1.10"
    )
}

#Preview("Claude Dashboard") {
    ProviderDashboard(
        provider: .claude,
        usage: .claudePreview,
        isLoading: false,
        errorMessage: nil,
        statusMessage: nil,
        serverAddress: "192.168.1.10",
        hostDescription: "192.168.1.10"
    )
}
