import Foundation
import Defaults

enum ProviderID: String, CaseIterable, Identifiable {
    case claude, codex, gemini, cursor, antigravity
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "GPT"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        }
    }
    var enabledKey: Defaults.Key<Bool> {
        switch self {
        case .claude: return .enableClaudeProvider
        case .codex: return .enableCodexProvider
        case .gemini: return .enableGeminiProvider
        case .cursor: return .enableCursorProvider
        case .antigravity: return .enableAntigravityProvider
        }
    }

    /// Cheap file-system check: is this AI tool installed / signed in on this Mac?
    var isInstalled: Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func exists(_ relative: String) -> Bool { fm.fileExists(atPath: home.appendingPathComponent(relative).path) }
        func app(_ name: String) -> Bool {
            fm.fileExists(atPath: "/Applications/\(name).app") || exists("Applications/\(name).app")
        }
        switch self {
        case .claude: return exists(".claude/projects")
        case .codex: return exists(".codex")
        case .gemini: return exists(".gemini/oauth_creds.json") || exists(".gemini/tmp")
        case .cursor: return app("Cursor") || exists("Library/Application Support/Cursor")
        case .antigravity:
            return app("Antigravity") || app("Antigravity IDE")
                || exists("Library/Application Support/Antigravity") || exists(".gemini/antigravity")
        }
    }

    /// Installed and switched on in settings.
    var isAvailable: Bool { isInstalled && Defaults[enabledKey] }

    static var available: [ProviderID] { allCases.filter(\.isAvailable) }

    /// The AI tab is shown only when at least one provider is installed and enabled.
    static var hasAnyAvailable: Bool { allCases.contains(where: \.isAvailable) }
}

struct UsageTotals: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var costUSD: Double = 0
    var hasUnpricedModel: Bool = false
    var isPercentage: Bool = false
    var totalTokens: Int { inputTokens + outputTokens }
}

struct ModelUsage: Equatable, Identifiable {
    let model: String
    let totals: UsageTotals
    let pool: String? // "gemini" or "claude" for Antigravity
    let resetsAt: Date? // quota reset time for percentage-based providers
    var id: String { model }

    init(model: String, totals: UsageTotals, pool: String? = nil, resetsAt: Date? = nil) {
        self.model = model
        self.totals = totals
        self.pool = pool
        self.resetsAt = resetsAt
    }
}

struct UsageLimit: Equatable {
    let used: Double
    let limit: Double
    var resetsAt: Date? = nil
    /// Length of the quota window when the provider reports it (e.g. Codex Go has one 30-day window).
    var windowSeconds: Double? = nil
    var fraction: Double { limit > 0 ? min(used / limit, 1) : 0 }
}

struct LabeledLimit: Equatable, Identifiable {
    let label: String
    let limit: UsageLimit
    var id: String { label }
}

struct UsageSnapshot: Equatable {
    var session: UsageTotals = .init()
    var today: UsageTotals = .init()
    var week: UsageTotals = .init()
    var sessionLimit: UsageLimit? = nil // 5h window quota
    var weekLimit: UsageLimit? = nil // 7d window quota
    var models: [ModelUsage] = []
    var plan: String? = nil // Subscription plan label (e.g. "Max 5x"); provided by Claude only, nil otherwise.
    var extraLimits: [LabeledLimit] = [] // provider-specific windows (Gemini daily per-model quota)
    var quotaHint: String? = nil // why limits are missing, shown instead of "quota unavailable"
    var lastUpdated: Date = .distantPast
}

enum UsageResult {
    case loading
    case success(UsageSnapshot)
    case failure(String)
}

protocol UsageProvider {
    var id: ProviderID { get }
    func fetchSnapshot(now: Date) async throws -> UsageSnapshot
}
