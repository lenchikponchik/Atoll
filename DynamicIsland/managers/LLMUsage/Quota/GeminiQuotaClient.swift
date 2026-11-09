import Foundation

/// Daily per-model request quota for Gemini CLI sign-ins. Uses the private Code Assist
/// endpoints Gemini CLI itself calls; unverified and may stop working at any time.
struct GeminiQuotaClient {
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    private static let base = "https://cloudcode-pa.googleapis.com/v1internal"
    static let reloginHint = String(localized: "Gemini CLI sign-in expired: run gemini")

    private struct Credentials: Decodable {
        let accessToken: String
        let expiryDate: Double?
    }

    /// Never throws: failures give no limits; an expired sign-in gives a hint.
    func fetchLimits() async -> (limits: [LabeledLimit], hint: String?) {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/oauth_creds.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = try? Data(contentsOf: path),
              let creds = try? decoder.decode(Credentials.self, from: data) else { return ([], nil) }
        if let expiry = creds.expiryDate, expiry / 1000 < Date().timeIntervalSince1970 {
            // Gemini CLI refreshes its own token on the next run; we do not touch its refresh token.
            return ([], Self.reloginHint)
        }
        guard let project = await call("loadCodeAssist", token: creds.accessToken, body: [
            "metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
        ]).flatMap(Self.projectID) else { return ([], nil) }
        guard let quota = await call("retrieveUserQuota", token: creds.accessToken, body: ["project": project]),
              let buckets = quota["buckets"] as? [[String: Any]] else { return ([], nil) }
        return (Self.limits(from: buckets), nil)
    }

    private func call(_ method: String, token: String, body: [String: Any]) async -> [String: Any]? {
        var request = URLRequest(url: URL(string: "\(Self.base):\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func projectID(_ response: [String: Any]) -> String? {
        if let id = response["cloudaicompanionProject"] as? String, !id.isEmpty { return id }
        if let obj = response["cloudaicompanionProject"] as? [String: Any], let id = obj["id"] as? String { return id }
        return nil
    }

    /// One gauge per model (daily window), most-used first, at most three.
    static func limits(from buckets: [[String: Any]]) -> [LabeledLimit] {
        var byModel: [String: UsageLimit] = [:]
        for bucket in buckets {
            guard let model = bucket["modelId"] as? String,
                  let remaining = (bucket["remainingFraction"] as? NSNumber)?.doubleValue else { continue }
            let resets = (bucket["resetTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            let limit = UsageLimit(used: (1 - min(max(remaining, 0), 1)) * 100, limit: 100, resetsAt: resets)
            if let existing = byModel[model], existing.used >= limit.used { continue }
            byModel[model] = limit
        }
        return byModel
            .sorted { $0.value.used > $1.value.used }
            .prefix(3)
            .map { LabeledLimit(label: $0.key.replacingOccurrences(of: "gemini-", with: ""), limit: $0.value) }
    }
}
