import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), state: .loading)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        Task {
            let entry = await buildEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(next))
            completion(timeline)
        }
    }

    private func buildEntry() async -> UsageEntry {
        // Check prerequisites
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            return UsageEntry(date: Date(), state: .notInstalled)
        }

        let creds: ClaudeCredentials
        do {
            creds = try readClaudeCredentials()
        } catch {
            return UsageEntry(date: Date(), state: .notLoggedIn)
        }

        if creds.isExpired {
            return UsageEntry(date: Date(), state: .tokenExpired)
        }

        let session = parseLocalSessions()

        do {
            let utilization = try await fetchUtilization(token: creds.accessToken)
            return UsageEntry(date: Date(), state: .loaded(utilization: utilization, session: session))
        } catch AuthError.tokenExpired {
            return UsageEntry(date: Date(), state: .tokenExpired)
        } catch {
            return UsageEntry(date: Date(), state: .apiError(error.localizedDescription))
        }
    }
}

// MARK: - Widget View

struct GlassUsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)

            Group {
                switch entry.state {
                case .loading:
                    widgetStatus(icon: "ellipsis.circle", color: .secondary, text: "Loading…")
                case .notInstalled:
                    widgetStatus(icon: "exclamationmark.triangle.fill", color: .orange, text: "Claude CLI not installed")
                case .notLoggedIn:
                    widgetStatus(icon: "person.crop.circle.badge.xmark", color: .red, text: "Not logged in")
                case .tokenExpired:
                    widgetStatus(icon: "clock.badge.exclamationmark", color: .yellow, text: "Session expired — open Claude CLI")
                case .apiError(let msg):
                    widgetStatus(icon: "wifi.exclamationmark", color: .orange, text: msg)
                case .loaded(let util, let session):
                    if family == .systemSmall {
                        SmallView(util: util, session: session, date: entry.date)
                    } else {
                        MediumView(util: util, session: session, date: entry.date)
                    }
                }
            }
            .padding(12)
        }
    }

    func widgetStatus(icon: String, color: Color, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color.gradient)
                .font(.title2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small Widget

struct SmallView: View {
    let util: Utilization
    let session: SessionStats
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.purple.gradient)
                    .font(.caption)
                Text("Claude")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Circle().fill(.green).frame(width: 5, height: 5)
            }

            Divider().opacity(0.3)

            if let w = util.seven_day, let pct = w.utilization {
                compactBar(label: "Weekly", pct: pct, color: limitColor(pct))
            }
            if let h = util.five_hour, let pct = h.utilization {
                compactBar(label: "5-Hour", pct: pct, color: .blue)
            }

            Spacer()

            Text("\(session.apiCalls) calls · \(fmt(session.outputTokens)) out")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    func compactBar(label: String, pct: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(pct))%").font(.system(.caption2, design: .monospaced)).fontWeight(.bold).foregroundStyle(color.gradient)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1)).frame(height: 4)
                    Capsule().fill(color.gradient).frame(width: geo.size.width * min(pct / 100, 1), height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Medium Widget

struct MediumView: View {
    let util: Utilization
    let session: SessionStats
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.purple.gradient)
                    .font(.caption)
                Text("Claude Usage")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider().opacity(0.3)

            HStack(alignment: .top, spacing: 16) {
                // Left: rate limits
                VStack(alignment: .leading, spacing: 6) {
                    if let w = util.seven_day, let pct = w.utilization {
                        medBar(label: "Weekly", pct: pct, color: limitColor(pct))
                    }
                    if let h = util.five_hour, let pct = h.utilization {
                        medBar(label: "5-Hour", pct: pct, color: .blue)
                    }
                    if let o = util.seven_day_opus, let pct = o.utilization {
                        medBar(label: "Opus", pct: pct, color: .purple)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().opacity(0.3)

                // Right: session stats
                VStack(alignment: .leading, spacing: 6) {
                    Text("LOCAL")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    statLine(value: fmt(session.outputTokens), label: "output")
                    statLine(value: fmt(session.cacheRead), label: "cache read")
                    statLine(value: "\(session.apiCalls)", label: "API calls")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    func medBar(label: String, pct: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(pct))%").font(.system(.caption2, design: .monospaced)).fontWeight(.bold).foregroundStyle(color.gradient)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1)).frame(height: 4)
                    Capsule().fill(color.gradient).frame(width: geo.size.width * min(pct / 100, 1), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    func statLine(value: String, label: String) -> some View {
        HStack {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Shared helpers

func limitColor(_ pct: Double) -> Color {
    if pct >= 90 { return .red }
    if pct >= 75 { return .orange }
    return .green
}

func fmt(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
    return "\(n)"
}

// MARK: - Widget Config

@main
struct GlassUsageWidget: Widget {
    let kind = "GlassUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            GlassUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Live Claude CLI usage limits and token stats.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    GlassUsageWidget()
} timeline: {
    UsageEntry(date: .now, state: .loaded(
        utilization: Utilization(
            five_hour: RateLimit(utilization: 42, resets_at: nil),
            seven_day: RateLimit(utilization: 67, resets_at: nil),
            seven_day_opus: RateLimit(utilization: 30, resets_at: nil),
            seven_day_sonnet: nil,
            extra_usage: nil
        ),
        session: SessionStats(inputTokens: 146, outputTokens: 12756, cacheRead: 3215270, cacheWrite: 168329, apiCalls: 76, sessionCount: 2)
    ))
}
