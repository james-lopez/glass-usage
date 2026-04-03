import SwiftUI
import WidgetKit

@MainActor
class ViewModel: ObservableObject {
    @Published var state: WidgetState = .loading
    @Published var lastUpdated: Date = Date()
    @Published var isRefreshing: Bool = false

    private let cacheTTL: TimeInterval = 900 // 15 minutes
    private var lastFetchAttempt: Date? = nil

    /// Called on popover open — skips fetch if data is fresh, otherwise refreshes silently.
    func refreshIfStale() {
        if let last = lastFetchAttempt, Date().timeIntervalSince(last) < cacheTTL {
            return // data is fresh, no-op
        }
        Task { await load() }
    }

    /// Force a fresh fetch regardless of cache (used by manual refresh button).
    func forceRefresh() {
        Task { await load() }
    }

    private func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastFetchAttempt = Date()
        defer { isRefreshing = false }

        // Only show loading spinner on first load (no cached data yet)
        if case .loading = state { /* already showing spinner */ }
        else { /* keep showing stale data while we refresh silently */ }

        // Check ~/.claude exists
        let claudeDir = realHomeDirectory()
            .appendingPathComponent(".claude")
        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            state = .notInstalled
            return
        }

        // Read credentials
        let creds: ClaudeCredentials
        do {
            creds = try readClaudeCredentials()
        } catch AuthError.notLoggedIn {
            state = .notLoggedIn
            return
        } catch {
            state = .notLoggedIn
            return
        }

        // Parse local session data (fast, local)
        let session = parseLocalSessions()

        // Fetch utilization from API
        do {
            let utilization = try await fetchUtilization(token: creds.accessToken)
            state = .loaded(utilization: utilization, session: session)
            lastUpdated = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } catch AuthError.tokenExpired {
            state = .tokenExpired
        } catch AuthError.networkError("429") {
            state = .rateLimited
        } catch AuthError.networkError(let msg) {
            state = .apiError(msg)
        } catch {
            state = .apiError(error.localizedDescription)
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = ViewModel()
    let timer = Timer.publish(every: 900, on: .main, in: .common).autoconnect() // 15 min

    var body: some View {
        GlassContainer {
            switch vm.state {
            case .loading:
                LoadingView()
            case .notInstalled:
                StatusView(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    title: "Claude CLI not found",
                    message: "Install the Claude CLI and log in to get started.",
                    hint: "brew install claude"
                )
            case .notLoggedIn:
                StatusView(
                    icon: "person.crop.circle.badge.xmark",
                    iconColor: .red,
                    title: "Not logged in",
                    message: "Open a terminal and run claude to log in.",
                    hint: "claude"
                )
            case .tokenExpired:
                StatusView(
                    icon: "clock.badge.exclamationmark",
                    iconColor: .yellow,
                    title: "Session expired",
                    message: "Re-open Claude CLI to refresh your session.",
                    hint: "claude"
                )
            case .rateLimited:
                StatusView(
                    icon: "gauge.with.dots.needle.33percent",
                    iconColor: .orange,
                    title: "Rate limit reached",
                    message: "You've hit your usage limit. Check back when it resets.",
                    hint: "HTTP 429"
                )
            case .apiError(let msg):
                StatusView(
                    icon: "wifi.exclamationmark",
                    iconColor: .orange,
                    title: "Can't reach Claude",
                    message: msg,
                    hint: nil
                )
            case .loaded(let utilization, let session):
                UsageView(utilization: utilization, session: session, lastUpdated: vm.lastUpdated, isRefreshing: vm.isRefreshing, onRefresh: { vm.forceRefresh() })
            }
        }
        .frame(width: 300)
        .onAppear { vm.refreshIfStale() }
        .onReceive(timer) { _ in vm.forceRefresh() }
    }
}

// MARK: - Glass Container

struct GlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)

            content.padding(18)
        }
    }
}

// MARK: - Header

struct WidgetHeader: View {
    let isOnline: Bool
    let isRefreshing: Bool
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Text("Bot-o-Meter")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Circle()
                    .fill(isOnline ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button { onRefresh?() } label: {
                        BitCharacter(color: dialOrange)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh now")
                }
            }
        }
    }
}

// MARK: - Status Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            WidgetHeader(isOnline: false, isRefreshing: false)
            Divider().opacity(0.3)
            HStack {
                ProgressView().scaleEffect(0.7)
                Text("Loading usage…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
    }
}

struct StatusView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    let hint: String?

    var body: some View {
        VStack(spacing: 12) {
            WidgetHeader(isOnline: false, isRefreshing: false)
            Divider().opacity(0.3)
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(iconColor.gradient)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let hint {
                    Text(hint)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Main Usage View

struct UsageView: View {
    let utilization: Utilization
    let session: SessionStats
    let lastUpdated: Date
    var isRefreshing: Bool = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(isOnline: true, isRefreshing: isRefreshing, onRefresh: onRefresh)
            Divider().opacity(0.3)

            // Rate limit dials — triangle if 3 gauges, side-by-side if ≤ 2
            let hasHourly = utilization.five_hour != nil
            let hasWeekly = utilization.seven_day != nil
            let hasOpus   = utilization.seven_day_opus != nil
            let gaugeCount = [hasHourly, hasWeekly, hasOpus].filter { $0 }.count

            if gaugeCount == 3 {
                VStack(spacing: 4) {
                    GaugeDial(label: "5-Hour", pct: utilization.five_hour!.utilization, color: dialOrange, dialSize: 86, resetsAt: utilization.five_hour!.resetsAtDate)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 0) {
                        GaugeDial(label: "Weekly", pct: utilization.seven_day!.utilization, color: dialRed, dialSize: 74, resetsAt: utilization.seven_day!.resetsAtDate)
                            .frame(maxWidth: .infinity)
                        GaugeDial(label: "Opus (7d)", pct: utilization.seven_day_opus!.utilization, color: dialPurple, dialSize: 74, resetsAt: utilization.seven_day_opus!.resetsAtDate)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    if let hourly = utilization.five_hour {
                        GaugeDial(label: "5-Hour", pct: hourly.utilization, color: dialOrange, dialSize: 80, resetsAt: hourly.resetsAtDate)
                            .frame(maxWidth: .infinity)
                    }
                    if let weekly = utilization.seven_day {
                        GaugeDial(label: "Weekly", pct: weekly.utilization, color: dialRed, dialSize: 80, resetsAt: weekly.resetsAtDate)
                            .frame(maxWidth: .infinity)
                    }
                    if let opus = utilization.seven_day_opus {
                        GaugeDial(label: "Opus (7d)", pct: opus.utilization, color: dialPurple, dialSize: 80, resetsAt: opus.resetsAtDate)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            // Extra usage
            if let extra = utilization.extra_usage, extra.is_enabled {
                Divider().opacity(0.3)
                ExtraUsageRow(extra: extra)
            }

            Divider().opacity(0.3)

            ResetTimesView(util: utilization)

            // Footer
            Text("Updated \(lastUpdated, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

}

// MARK: - Extra Usage

struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        HStack {
            Label("Extra usage", systemImage: "plus.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let used = extra.used_credits, let limit = extra.monthly_limit {
                Text(String(format: "$%.2f / $%.0f", used, limit))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
            } else {
                Text("Enabled")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Session Stats

struct SessionStatsRow: View {
    let session: SessionStats

    var body: some View {
        VStack(spacing: 8) {
            // Top: output tokens — prominent
            VStack(spacing: 2) {
                Text(fmt(session.outputTokens))
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                Text("output tokens")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)

            // Bottom row: cache read + API calls
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(fmt(session.cacheRead))
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("cache read")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(session.apiCalls)")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("API calls")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }

            Label("LOCAL SESSIONS · \(session.sessionCount)", systemImage: "internaldrive")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#Preview("3 gauges") {
    GlassContainer {
        UsageView(
            utilization: Utilization(
                five_hour: RateLimit(utilization: 42, resets_at: nil),
                seven_day: RateLimit(utilization: 67, resets_at: nil),
                seven_day_opus: RateLimit(utilization: 30, resets_at: nil),
                seven_day_sonnet: nil,
                extra_usage: nil
            ),
            session: SessionStats(inputTokens: 146, outputTokens: 12756, cacheRead: 3215270, cacheWrite: 168329, apiCalls: 76, sessionCount: 2),
            lastUpdated: Date()
        )
    }
    .frame(width: 300)
    .padding()
    .background(.black.opacity(0.4))
    .preferredColorScheme(.dark)
}

#Preview("2 gauges") {
    GlassContainer {
        UsageView(
            utilization: Utilization(
                five_hour: RateLimit(utilization: 15, resets_at: nil),
                seven_day: RateLimit(utilization: 22, resets_at: nil),
                seven_day_opus: nil,
                seven_day_sonnet: nil,
                extra_usage: nil
            ),
            session: SessionStats(inputTokens: 146, outputTokens: 283000, cacheRead: 88000000, cacheWrite: 168329, apiCalls: 1007, sessionCount: 3),
            lastUpdated: Date()
        )
    }
    .frame(width: 300)
    .padding()
    .background(.black.opacity(0.4))
    .preferredColorScheme(.dark)
}
