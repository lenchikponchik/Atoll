/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults

enum AntigravityPool: String, CaseIterable {
    case gemini = "Gemini"
    case claude = "Claude"
}

struct NotchLLMUsageView: View {
    @ObservedObject private var manager = LLMUsageManager.shared
    @State private var antigravityPool: AntigravityPool = .gemini

    /// Only tools installed on this Mac and enabled in settings.
    private var enabledProviders: [ProviderID] { ProviderID.available }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(enabledProviders) { provider in
                card(for: provider)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .environment(\.colorScheme, .dark)
        .onAppear { manager.refreshAll() }
    }

    @ViewBuilder
    private func card(for provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(provider.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                // Subscription plan badge (e.g. "Max 5x"). Only set for Claude; nil elsewhere.
                if case .success(let snap) = manager.results[provider] ?? .loading, let plan = snap.plan {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if provider == .antigravity {
                    Picker("", selection: $antigravityPool) {
                        Text("Gemini").tag(AntigravityPool.gemini)
                        Text("Claude").tag(AntigravityPool.claude)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .controlSize(.mini)
                }
            }
            switch manager.results[provider] ?? .loading {
            case .loading:
                ProgressView().controlSize(.small)
            case .failure(let reason):
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            case .success(let snap):
                success(snap, provider: provider)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        // Stretch every card to the height the panel offers so the row stays uniform
        // (the intent behind the former fixed card height) without a hard-coded size
        // that either clips content or leaves blank space.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func success(_ snap: UsageSnapshot, provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if provider == .antigravity {
                antigravitySuccess(snap)
            } else if snap.sessionLimit == nil && snap.weekLimit == nil && snap.extraLimits.isEmpty {
                if provider != .cursor {
                    window("Today", snap.today, prominent: true)
                    window("Week", snap.week)
                    window("Session", snap.session)
                }
                Text(snap.quotaHint ?? String(localized: "quota unavailable"))
                    .font(.caption2).foregroundStyle(.secondary.opacity(0.7)).lineLimit(2)
            } else {
                if provider == .cursor {
                    if let limit = snap.sessionLimit { quotaGauge(String(localized: "Cursor Models"), limit) }
                    if let limit = snap.weekLimit { quotaGauge(String(localized: "Other Models"), limit) }
                } else {
                    if let limit = snap.sessionLimit { quotaGauge(windowLabel(limit, fallback: 5 * 3600), limit) }
                    if let limit = snap.weekLimit { quotaGauge(windowLabel(limit, fallback: 7 * 86_400), limit) }
                    ForEach(snap.extraLimits) { quotaGauge($0.label, $0.limit) }
                    VStack(alignment: .leading, spacing: 2) {
                        window("Today", snap.today, compact: true)
                        window("Week", snap.week, compact: true)
                    }
                }
            }
        }
    }

    private func antigravitySuccess(_ snap: UsageSnapshot) -> some View {
        let isGemini = antigravityPool == .gemini
        let targetPool = isGemini ? "gemini" : "claude"
        
        // Filter models by pool
        let sessionModel = snap.models.first { $0.model == "Session" && $0.pool == targetPool }
        let weeklyModel = snap.models.first { $0.model == "Weekly" && $0.pool == targetPool }
        
        // Helper to create UsageLimit from model
        func limitFromModel(_ model: ModelUsage?) -> UsageLimit? {
            guard let model = model else { return nil }
            let fraction = model.totals.costUSD
            let usedPct = (1 - max(0, min(1, fraction))) * 100
            return UsageLimit(used: usedPct, limit: 100, resetsAt: model.resetsAt)
        }
        
        return VStack(alignment: .leading, spacing: 6) {
            if let limit = limitFromModel(sessionModel) {
                quotaGauge(String(localized: "5 hours"), limit)
            }
            if let limit = limitFromModel(weeklyModel) {
                quotaGauge(String(localized: "Week"), limit)
            }
            
            // Token counts and estimated cost read from the language server's
            // conversation history (all pools; Antigravity does not split them).
            VStack(alignment: .leading, spacing: 4) {
                window("Today", snap.today, compact: true)
                window("Week", snap.week, compact: true)
            }
        }
    }

    @ViewBuilder
    private func quotaGauge(_ label: String, _ limit: UsageLimit) -> some View {
        let usedPct = Int(limit.used.rounded())
        let leftPct = max(0, 100 - usedPct)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let resets = resetsIn(limit.resetsAt) {
                    Text(resets).font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(gaugeTint(limit.fraction)).frame(width: max(4, geo.size.width * limit.fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(usedPct)% \(String(localized: "used"))").font(.caption2).monospacedDigit()
                Spacer()
                Text("\(leftPct)% \(String(localized: "left"))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func gaugeTint(_ fraction: Double) -> Color {
        if fraction > 0.95 { return .red }
        if fraction > 0.9 { return .orange }
        return .accentColor
    }

    private func resetsIn(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        let prefix = String(localized: "resets in")
        let d = String(localized: "d")
        let h = String(localized: "h")
        let m = String(localized: "min")
        if days > 0 { return "\(prefix) \(days) \(d) \(hours) \(h)" }
        return hours > 0 ? "\(prefix) \(hours) \(h) \(minutes) \(m)" : "\(prefix) \(minutes) \(m)"
    }

    /// Names a quota window by its real length; Codex Go, for example, has a single 30-day window.
    private func windowLabel(_ limit: UsageLimit, fallback: Double) -> String {
        var seconds = limit.windowSeconds ?? fallback
        if limit.windowSeconds == nil, let resets = limit.resetsAt {
            seconds = max(seconds, resets.timeIntervalSinceNow) // a reset further away than the window means a longer window
        }
        switch seconds {
        case ..<(6 * 3600): return String(localized: "5 hours")
        case ..<(36 * 3600): return String(localized: "Day")
        case ..<(8 * 86_400): return String(localized: "Week")
        default: return String(localized: "Month")
        }
    }

    private func window(_ label: LocalizedStringKey, _ totals: UsageTotals, prominent: Bool = false, compact: Bool = false) -> some View {
        let displayValue: String
        if totals.isPercentage {
            displayValue = "\(totals.totalTokens)%"
        } else {
            displayValue = tokens(totals.totalTokens)
        }
        
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 58 : 62, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(displayValue)
                .font(.system(size: compact ? 11 : (prominent ? 17 : 13), weight: prominent ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
            Spacer(minLength: 4)
            if totals.isPercentage {
                // Quota providers store the remaining fraction in costUSD; it is not money.
                let leftPct = Int((max(0, min(1, totals.costUSD)) * 100).rounded())
                Text("\(leftPct)% \(String(localized: "left"))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(costLabel(totals))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .help(costHelp(totals))
            }
        }
    }

    /// Cost is an estimate computed from local token counts against the API price
    /// table — not a subscription bill. When some models used have no entry in the
    /// table we cannot price them: show "\(money)+" when a partial amount is known,
    /// and an explicit "est. n/a" instead of a misleading "$0.00+" when nothing is.
    private func costLabel(_ totals: UsageTotals) -> String {
        guard totals.hasUnpricedModel else { return money(totals.costUSD) }
        return totals.costUSD > 0 ? money(totals.costUSD) + "+" : String(localized: "est. n/a")
    }

    private func costHelp(_ totals: UsageTotals) -> String {
        if totals.hasUnpricedModel {
            return String(localized: "Estimated API-equivalent cost from local token counts (not your subscription bill). Some models used do not have usable pricing, so this is partial or unavailable.")
        }
        return String(localized: "Estimated API-equivalent cost from local token counts (cache reads and writes priced at the provider's cache rates), not your subscription bill.")
    }

    private func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    // Locale-aware formatting pinned to USD — amounts come from the USD pricing table, so the currency code stays fixed.
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    private func money(_ v: Double) -> String {
        Self.currencyFormatter.string(from: v as NSNumber) ?? String(format: "$%.2f", v)
    }
}
