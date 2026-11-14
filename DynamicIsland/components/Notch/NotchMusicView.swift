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

/// Music tab: the full player, moved out of the Home tab so Home can show the
/// schedule and the weather.
struct NotchMusicView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                MusicPlayerView(albumArtNamespace: albumArtNamespace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blur(radius: vm.notchState == .closed ? 30 : 0)
                    .padding(8)
            }
        }
        .transition(.opacity.combined(with: .blurReplace))
    }
}

/// Weather card on the Home tab. Reuses the lock screen weather data, so there is
/// one provider, one location permission and one refresh interval.
struct HomeWeatherView: View {
    @ObservedObject private var weather = LockScreenWeatherManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = weather.snapshot {
                content(snapshot)
            } else {
                Image(systemName: "cloud.sun")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Loading weather…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
        .task {
            // Throttled by the manager's own refresh interval
            _ = await weather.refresh(force: false)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: LockScreenWeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: snapshot.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 28))
                .frame(width: 36, height: 34)
            Text(temperature(snapshot))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }

        if !snapshot.description.isEmpty {
            Text(snapshot.description)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }

        if let range = range(snapshot) {
            Text(range)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }

        Spacer(minLength: 0)

        if let location = snapshot.locationName, !location.isEmpty {
            Label(location, systemImage: "location.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func temperature(_ snapshot: LockScreenWeatherSnapshot) -> String {
        if let info = snapshot.temperatureInfo {
            return "\(info.displayCurrent)°"
        }
        return snapshot.temperatureText
    }

    private func range(_ snapshot: LockScreenWeatherSnapshot) -> String? {
        guard let info = snapshot.temperatureInfo,
              let low = info.displayMinimum, let high = info.displayMaximum else { return nil }
        return "↓ \(low)°   ↑ \(high)°"
    }
}
