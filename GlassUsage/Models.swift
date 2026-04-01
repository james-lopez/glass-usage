import Foundation

// MARK: - API Models

struct RateLimit: Codable {
    let utilization: Double?  // 0–100 percentage
    let resets_at: String?    // ISO 8601

    var resetsAtDate: Date? {
        guard let s = resets_at else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
}

struct ExtraUsage: Codable {
    let is_enabled: Bool
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?  // 0–100
}

struct Utilization: Codable {
    let five_hour: RateLimit?
    let seven_day: RateLimit?
    let seven_day_opus: RateLimit?
    let seven_day_sonnet: RateLimit?
    let extra_usage: ExtraUsage?
}

// MARK: - Local Session Stats

struct SessionStats {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var apiCalls: Int = 0
    var sessionCount: Int = 0

    var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - App State

enum AuthError: Error {
    case claudeNotInstalled
    case notLoggedIn
    case tokenExpired
    case networkError(String)
    case parseError
}

struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
}

enum WidgetState {
    case loading
    case notInstalled       // ~/.claude not found
    case notLoggedIn        // no keychain entry
    case tokenExpired       // token exists but stale
    case loaded(utilization: Utilization, session: SessionStats)
    case apiError(String)   // got creds, but API failed (offline, etc.)
}
