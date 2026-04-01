import SwiftUI

@MainActor
class ViewModel: ObservableObject {
    @Published var state: WidgetState = .loading
    @Published var lastUpdated: Date = Date()

    func refresh() {
        Task {
            state = .loading
            await load()
        }
    }

    private func load() async {
        // Check ~/.claude exists
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
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

        if creds.isExpired {
            state = .tokenExpired
            return
        }

        // Parse local session data (fast, local)
        let session = parseLocalSessions()

        // Fetch utilization from API
        do {
            let utilization = try await fetchUtilization(token: creds.accessToken)
            state = .loaded(utilization: utilization, session: session)
            lastUpdated = Date()
        } catch AuthError.tokenExpired {
            state = .tokenExpired
        } catch AuthError.networkError(let msg) {
            // Show last known session data with an error note
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
            case .apiError(let msg):
                StatusView(
                    icon: "wifi.exclamationmark",
                    iconColor: .orange,
                    title: "Can't reach Claude",
                    message: msg,
                    hint: nil
                )
            case .loaded(let utilization, let session):
                UsageView(utilization: utilization, session: session, lastUpdated: vm.lastUpdated)
            }
        }
        .frame(width: 300)
        .onAppear { vm.refresh() }
        .onReceive(timer) { _ in vm.refresh() }
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundStyle(.purple.gradient)
            Text("Claude Usage")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Circle()
                .fill(isOnline ? .green : .orange)
                .frame(width: 7, height: 7)
        }
    }
}

// MARK: - Status Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            WidgetHeader(isOnline: false)
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
            WidgetHeader(isOnline: false)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(isOnline: true)
            Divider().opacity(0.3)

            // Rate limit bars — mirrors /usage
            if let weekly = utilization.seven_day {
                LimitBar(label: "Weekly", limit: weekly, color: weeklyColor(weekly.utilization))
            }
            if let hourly = utilization.five_hour {
                LimitBar(label: "5-Hour", limit: hourly, color: .blue)
            }
            if let opus = utilization.seven_day_opus {
                LimitBar(label: "Opus (7d)", limit: opus, color: .purple)
            }
            if let sonnet = utilization.seven_day_sonnet {
                LimitBar(label: "Sonnet (7d)", limit: sonnet, color: .indigo)
            }

            // Extra usage
            if let extra = utilization.extra_usage, extra.is_enabled {
                Divider().opacity(0.3)
                ExtraUsageRow(extra: extra)
            }

            Divider().opacity(0.3)

            // Session stats from local JSONL
            SessionStatsRow(session: session)

            // Footer
            Text("Updated \(lastUpdated, style: .relative) ago · \(session.sessionCount) sessions")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    func weeklyColor(_ pct: Double?) -> Color {
        guard let pct else { return .green }
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }
}

// MARK: - Limit Bar

struct LimitBar: View {
    let label: String
    let limit: RateLimit
    let color: Color

    var pct: Double { min(max((limit.utilization ?? 0) / 100, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(limit.utilization.map { "\(Int($0))%" } ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(color.gradient)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(height: 5)
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: geo.size.width * pct, height: 5)
                }
            }
            .frame(height: 5)

            if let resetsAt = limit.resetsAtDate {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
        VStack(alignment: .leading, spacing: 6) {
            Label("LOCAL SESSIONS", systemImage: "internaldrive")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                MiniStat(value: fmt(session.outputTokens), label: "output", icon: "arrow.up.circle", color: .purple)
                MiniStat(value: fmt(session.cacheRead), label: "cache read", icon: "bolt.circle", color: .blue)
                MiniStat(value: "\(session.apiCalls)", label: "calls", icon: "arrow.triangle.2.circlepath", color: .teal)
            }
        }
    }

    func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct MiniStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color.gradient)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    ContentView()
        .padding()
        .background(.black.opacity(0.4))
        .preferredColorScheme(.dark)
}
