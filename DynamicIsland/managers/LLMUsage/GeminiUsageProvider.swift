import Foundation

/// Gemini CLI: token usage from the chat recordings in ~/.gemini/tmp/*/chats,
/// daily per-model quota from Google's Code Assist API (unofficial, best effort).
struct GeminiUsageProvider: UsageProvider {
    let id: ProviderID = .gemini
    let root: URL
    let quotaClient: GeminiQuotaClient

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/tmp"),
         quotaClient: GeminiQuotaClient = GeminiQuotaClient()) {
        self.root = root
        self.quotaClient = quotaClient
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        var snapshot = JSONLUsageParser.aggregate(records: records(), now: now)
        let quota = await quotaClient.fetchLimits()
        snapshot.extraLimits = quota.limits
        snapshot.quotaHint = quota.hint
        return snapshot
    }

    private func records() -> [UsageRecord] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var result: [UsageRecord] = []
        for case let url as URL in en
        where url.pathExtension == "json" && url.deletingLastPathComponent().lastPathComponent == "chats" {
            guard let data = try? Data(contentsOf: url),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let messages = obj["messages"] as? [[String: Any]] else { continue }
            for message in messages {
                guard let tokens = message["tokens"] as? [String: Any] else { continue }
                let input = Self.int(tokens["input"])
                let output = Self.int(tokens["output"]) + Self.int(tokens["thoughts"])
                guard input + output > 0,
                      let ts = (message["timestamp"] as? String).flatMap(Self.parseDate) else { continue }
                let model = message["model"] as? String ?? "gemini"
                let key = (message["id"] as? String).map { "gemini-\($0)" }
                result.append(UsageRecord(timestamp: ts, model: model, inputTokens: input, outputTokens: output, dedupKey: key))
            }
        }
        return result
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? NSNumber)?.intValue ?? 0
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
