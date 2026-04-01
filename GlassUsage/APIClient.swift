import Foundation
import Security

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

    guard status == errSecSuccess else {
        if status == errSecItemNotFound {
            throw AuthError.notLoggedIn
        }
        throw AuthError.notLoggedIn
    }

    guard
        let data = item as? Data,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let oauth = json["claudeAiOauth"] as? [String: Any],
        let token = oauth["accessToken"] as? String,
        let expiresMs = oauth["expiresAt"] as? Double
    else {
        throw AuthError.notLoggedIn
    }

    let expiresAt = Date(timeIntervalSince1970: expiresMs / 1000)
    return ClaudeCredentials(accessToken: token, expiresAt: expiresAt)
}

// MARK: - Usage API

private let usageURL = URL(string: "https://claude.ai/api/oauth/usage")!

func fetchUtilization(token: String) async throws -> Utilization {
    var request = URLRequest(url: usageURL)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("claude-code", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
        throw AuthError.networkError("Invalid response")
    }

    switch http.statusCode {
    case 200:
        break
    case 401:
        throw AuthError.tokenExpired
    case 403:
        throw AuthError.notLoggedIn
    default:
        throw AuthError.networkError("HTTP \(http.statusCode)")
    }

    guard let utilization = try? JSONDecoder().decode(Utilization.self, from: data) else {
        throw AuthError.parseError
    }

    return utilization
}

// MARK: - Auth state resolver

func resolveAuthState() -> WidgetState {
    let claudeDir = FileManager.default.homeDirectoryForCurrentUser
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
