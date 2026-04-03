import SwiftUI
import WidgetKit

// MARK: - Palette

let dialRed    = Color(red: 0.88, green: 0.32, blue: 0.32)
let dialOrange = Color(red: 1.00, green: 0.58, blue: 0.12)
let dialPurple = Color(red: 0.60, green: 0.30, blue: 0.88)

// MARK: - Shared helpers

func limitColor(_ pct: Double) -> Color { dialRed }   // kept for any legacy call

func fmt(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000    { return String(format: "%.0fK", Double(n) / 1_000) }
    return "\(n)"
}

// MARK: - Gauge Dial

struct GaugeDial: View {
    let label: String
    let pct: Double?
    let color: Color
    var dialSize: CGFloat = 72
    var resetsAt: Date? = nil

    private static let startDeg = 150.0
    private static let sweepDeg = 240.0
    private var fraction: Double { min(max((pct ?? 0) / 100, 0), 1) }
    private var lineW: CGFloat { dialSize * 0.09 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background track
                Circle()
                    .trim(from: 0, to: Self.sweepDeg / 360)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                    .rotationEffect(.degrees(Self.startDeg))

                // Progress arc
                Circle()
                    .trim(from: 0, to: fraction * Self.sweepDeg / 360)
                    .stroke(color.opacity(0.9),
                            style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                    .rotationEffect(.degrees(Self.startDeg))

                // Center text
                VStack(spacing: 1) {
                    Text(pct.map { "\(Int($0))%" } ?? "—")
                        .font(.system(size: max(9, dialSize * 0.19), weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                    if let r = resetsAt {
                        Text(r, style: .timer)
                            .font(.system(size: max(7, dialSize * 0.12)))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: dialSize, height: dialSize)

            Text(label)
                .font(.system(size: max(9, dialSize * 0.145), weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Reset Times

/// Shows a compact countdown row for each active limit's reset time.
struct ResetTimesView: View {
    let util: Utilization
    var compact: Bool = false

    var body: some View {
        let rows = resetRows
        if rows.isEmpty {
            Text("Reset times unavailable")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            VStack(spacing: compact ? 4 : 6) {
                ForEach(rows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.date, style: .timer)
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(row.color)
                    }
                }
            }
        }
    }

    private struct ResetRow { let label: String; let date: Date; let color: Color }

    private var resetRows: [ResetRow] {
        var rows: [ResetRow] = []
        if let h = util.five_hour,  let d = h.resetsAtDate  { rows.append(.init(label: "5-Hour resets",  date: d, color: dialOrange)) }
        if let w = util.seven_day,  let d = w.resetsAtDate  { rows.append(.init(label: "Weekly resets",  date: d, color: dialRed))    }
        if let o = util.seven_day_opus, let d = o.resetsAtDate { rows.append(.init(label: "Opus resets", date: d, color: dialPurple)) }
        return rows
    }
}

// MARK: - Bit Character

struct BitCharacter: View {
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            // Antenna
            VStack(spacing: 0) {
                Circle()
                    .fill(color)
                    .frame(width: 3.5, height: 3.5)
                Rectangle()
                    .fill(color)
                    .frame(width: 1.5, height: 4)
            }

            // Head
            ZStack {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(color.opacity(0.15))
                    .frame(width: 16, height: 12)
                RoundedRectangle(cornerRadius: 2.5)
                    .stroke(color.opacity(0.55), lineWidth: 1.2)
                    .frame(width: 16, height: 12)
                // Eyes
                HStack(spacing: 3.5) {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color)
                        .frame(width: 3, height: 3)
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color)
                        .frame(width: 3, height: 3)
                }
                .offset(y: -1.5)
                // Mouth
                HStack(spacing: 1) {
                    Rectangle().fill(color).frame(width: 1.5, height: 1.5)
                    Rectangle().fill(color).frame(width: 4.5, height: 1)
                    Rectangle().fill(color).frame(width: 1.5, height: 1.5)
                }
                .offset(y: 2.5)
            }
        }
        .frame(width: 20, height: 24)
    }
}

// MARK: - Widget View

struct GlassUsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
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
            case .rateLimited:
                widgetStatus(icon: "gauge.with.dots.needle.33percent", color: dialOrange, text: "Rate limit reached · 429")
            case .apiError(let msg):
                widgetStatus(icon: "wifi.exclamationmark", color: .orange, text: msg)
            case .loaded(let util, let session):
                switch family {
                case .systemSmall:
                    SmallView(util: util, session: session, date: entry.date)
                case .systemLarge, .systemExtraLarge:
                    LargeView(util: util, session: session, date: entry.date)
                default:
                    MediumView(util: util, session: session, date: entry.date)
                }
            }
        }
        .padding(.top, 18)
        .padding([.horizontal, .bottom], 12)
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

// MARK: - Widget Header (shared)

struct WidgetBadgeHeader: View {
    let isOnline: Bool
    var fontSize: Font = .caption

    var body: some View {
        ZStack {
            Text("Bot-o-Meter")
                .font(fontSize)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Circle()
                    .fill(isOnline ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                Spacer()
                BitCharacter(color: dialOrange)
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 16)
            }
        }
    }
}

// MARK: - Small Widget

struct SmallView: View {
    let util: Utilization
    let session: SessionStats
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetBadgeHeader(isOnline: true)
            Divider().opacity(0.3)

            if let w = util.seven_day, let pct = w.utilization {
                compactBar(label: "Weekly", pct: pct, color: dialRed)
            }
            if let h = util.five_hour, let pct = h.utilization {
                compactBar(label: "5-Hour", pct: pct, color: dialOrange)
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
                Text("\(Int(pct))%")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                    Capsule().fill(color.opacity(0.85)).frame(width: geo.size.width * min(pct / 100, 1), height: 4)
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
        VStack(spacing: 6) {
            WidgetBadgeHeader(isOnline: true)
            Divider().opacity(0.3)

            // Dials — triangle layout
            VStack(spacing: 2) {
                if let h = util.five_hour {
                    GaugeDial(label: "5-Hour", pct: h.utilization, color: dialOrange, dialSize: 72)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 0) {
                    if let w = util.seven_day {
                        GaugeDial(label: "Weekly", pct: w.utilization, color: dialRed, dialSize: 62)
                            .frame(maxWidth: .infinity)
                    }
                    if let o = util.seven_day_opus {
                        GaugeDial(label: "Opus", pct: o.utilization, color: dialPurple, dialSize: 62)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Divider().opacity(0.3)

            ResetTimesView(util: util, compact: true)

            Divider().opacity(0.3)

            // Compact stats row
            HStack(spacing: 0) {
                statLine(value: fmt(session.outputTokens), label: "output")
                Spacer()
                statLine(value: fmt(session.cacheRead), label: "cache")
                Spacer()
                statLine(value: "\(session.apiCalls)", label: "calls")
            }
        }
    }

    func statLine(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Large Widget

struct LargeView: View {
    let util: Utilization
    let session: SessionStats
    let date: Date

    var body: some View {
        VStack(spacing: 10) {
            WidgetBadgeHeader(isOnline: true, fontSize: .subheadline)
            Divider().opacity(0.3)

            // Dials — triangle layout
            VStack(spacing: 4) {
                if let h = util.five_hour {
                    GaugeDial(label: "5-Hour", pct: h.utilization, color: dialOrange, dialSize: 92)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 0) {
                    if let w = util.seven_day {
                        GaugeDial(label: "Weekly", pct: w.utilization, color: dialRed, dialSize: 78)
                            .frame(maxWidth: .infinity)
                    }
                    if let o = util.seven_day_opus {
                        GaugeDial(label: "Opus (7d)", pct: o.utilization, color: dialPurple, dialSize: 78)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if let extra = util.extra_usage, extra.is_enabled {
                Divider().opacity(0.3)
                HStack {
                    Label("Extra usage", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let used = extra.used_credits, let limit = extra.monthly_limit {
                        Text(String(format: "$%.2f / $%.0f", used, limit))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                }
            }

            Divider().opacity(0.3)

            ResetTimesView(util: util)

            Divider().opacity(0.3)

            // Stats row — no session count label
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(fmt(session.outputTokens))
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                    Text("output")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(fmt(session.cacheRead))
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("cache")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(session.apiCalls)")
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("calls")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()

            Text("Updated \(date, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
