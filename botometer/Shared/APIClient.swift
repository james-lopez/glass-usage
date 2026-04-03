import Foundation
import Security

// MARK: - Real Home Directory (sandbox-safe)

/// Returns the real user home directory (e.g. /Users/jeeves), even when
/// running inside a sandboxed widget extension where NSHomeDirectory()
/// and FileManager.homeDirectoryForCurrentUser return the container path.
func realHomeDirectory() -> URL {
    if let pw = getpwuid(getuid()) {
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
    }
    return FileManager.default.homeDirectoryForCurrentUser
}

// MARK: - Keychain

private let keychainService = "Claude Code-credentials"

func readClaudeCredentials() throws -> ClaudeCredentials {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: keychainService,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne
    ]

    var item: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    print("[GlassUsage] Keychain lookup status: \(status)")

    guard status == errSecSuccess else {
        print("[GlassUsage] Keychain error: \(status == errSecItemNotFound ? "not found" : "error \(status)")")
        throw AuthError.notLoggedIn
    }

    guard
        let data = item as? Data,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let oauth = json["claudeAiOauth"] as? [String: Any],
        let token = oauth["accessToken"] as? String,
        let expiresMs = oauth["expiresAt"] as? Double
    else {
        print("[GlassUsage] Keychain parse failed — keys found: \((try? JSONSerialization.jsonObject(with: item as? Data ?? Data()) as? [String: Any])?.keys.joined(separator: ", ") ?? "none")")
        throw AuthError.notLoggedIn
    }

    let expiresAt = Date(timeIntervalSince1970: expiresMs / 1000)
    let tokenPreview = "\(token.prefix(12))...\(token.suffix(6))"
    print("[GlassUsage] Token read OK: \(tokenPreview), expires: \(expiresAt), isExpired: \(Date() >= expiresAt)")
    return ClaudeCredentials(accessToken: token, expiresAt: expiresAt)
}


// MARK: - Usage API

private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

func fetchUtilization(token: String) async throws -> Utilization {
    var request = URLRequest(url: usageURL)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("claude-code", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10

    print("[GlassUsage] Fetching utilization from \(usageURL)")
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
        throw AuthError.networkError("Invalid response")
    }

    print("[GlassUsage] HTTP status: \(http.statusCode)")

    switch http.statusCode {
    case 200:
        break
    case 401:
        print("[GlassUsage] 401 body: \(String(data: data, encoding: .utf8) ?? "unreadable")")
        throw AuthError.tokenExpired
    case 403:
        print("[GlassUsage] 403 body: \(String(data: data, encoding: .utf8) ?? "unreadable")")
        throw AuthError.notLoggedIn
    case 429:
        throw AuthError.networkError("429")
    default:
        print("[GlassUsage] \(http.statusCode) body: \(String(data: data, encoding: .utf8) ?? "unreadable")")
        throw AuthError.networkError("HTTP \(http.statusCode)")
    }

    // Log raw JSON so field changes from Anthropic are visible in Console.app
    print("[GlassUsage] Raw JSON: \(String(data: data, encoding: .utf8) ?? "unreadable")")

    guard let utilization = try? JSONDecoder().decode(Utilization.self, from: data) else {
        print("[GlassUsage] Parse failed.")
        throw AuthError.parseError
    }

    print("[GlassUsage] Decoded — 5h: \(utilization.five_hour?.utilization.map { "\(Int($0))%" } ?? "nil"), 7d: \(utilization.seven_day?.utilization.map { "\(Int($0))%" } ?? "nil"), opus: \(utilization.seven_day_opus?.utilization.map { "\(Int($0))%" } ?? "nil")")

    return utilization
}

// MARK: - Auth state resolver

func resolveAuthState() -> WidgetState {
    let claudeDir = realHomeDirectory()
        .appendingPathComponent(".claude")

    guard FileManager.default.fileExists(atPath: claudeDir.path) else {
        return .notInstalled
    }

    do {
        let creds = try readClaudeCredentials()
        if creds.isExpired {
            return .tokenExpired
        }
        return .loaded(utilization: Utilization(
            five_hour: nil, seven_day: nil,
            seven_day_opus: nil, seven_day_sonnet: nil, extra_usage: nil
        ), session: SessionStats())
    } catch AuthError.notLoggedIn {
        return .notLoggedIn
    } catch {
        return .notLoggedIn
    }
}
