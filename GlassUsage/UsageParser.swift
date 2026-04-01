import Foundation

private struct MessageUsage: Codable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
}

private struct AssistantMessage: Codable {
    let usage: MessageUsage?
}

private struct SessionEntry: Codable {
    let type: String?
    let message: AssistantMessage?
    let timestamp: String?
}

func parseLocalSessions() -> SessionStats {
    var stats = SessionStats()
    let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    guard let projectDirs = try? FileManager.default.contentsOfDirectory(
        at: claudeDir, includingPropertiesForKeys: nil
    ) else { return stats }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let decoder = JSONDecoder()

    for dir in projectDirs {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { continue }

        let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }
        stats.sessionCount += jsonlFiles.count

        for file in jsonlFiles {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") where !line.isEmpty {
                guard
                    let data = line.data(using: .utf8),
                    let entry = try? decoder.decode(SessionEntry.self, from: data),
                    entry.type == "assistant",
                    let usage = entry.message?.usage
                else { continue }

                stats.inputTokens += usage.input_tokens ?? 0
                stats.outputTokens += usage.output_tokens ?? 0
                stats.cacheRead += usage.cache_read_input_tokens ?? 0
                stats.cacheWrite += usage.cache_creation_input_tokens ?? 0
                stats.apiCalls += 1
            }
        }
    }

    return stats
}
