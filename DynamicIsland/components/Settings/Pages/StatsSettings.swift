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

import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

struct StatsSettings: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableLLMUsageFeature) var enableLLMUsageFeature
    @Default(.statsStopWhenNotchCloses) var statsStopWhenNotchCloses
    @Default(.statsUpdateInterval) var statsUpdateInterval
    @Default(.showCpuGraph) var showCpuGraph
    @Default(.showMemoryGraph) var showMemoryGraph
    @Default(.showGpuGraph) var showGpuGraph
    @Default(.showNetworkGraph) var showNetworkGraph
    @Default(.showDiskGraph) var showDiskGraph
    @Default(.cpuTemperatureUnit) var cpuTemperatureUnit

    private func highlightID(_ title: String) -> String {
        SettingsTab.stats.highlightID(for: title)
    }

    var enabledGraphsCount: Int {
        [showCpuGraph, showMemoryGraph, showGpuGraph, showNetworkGraph, showDiskGraph].filter { $0 }.count
    }

    private var formattedUpdateInterval: String {
        let seconds = Int(statsUpdateInterval.rounded())
        if seconds >= 60 {
            return "60 s (1 min)"
        } else if seconds == 1 {
            return "1 s"
        } else {
            return "\(seconds) s"
        }
    }

    private var shouldShowStatsBatteryWarning: Bool {
        !statsStopWhenNotchCloses && statsUpdateInterval <= 5
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableStatsFeature) {
                    Text("Enable system stats monitoring")
                }
                .settingsHighlight(id: highlightID("Enable system stats monitoring"))
                .onChange(of: enableStatsFeature) { _, newValue in
                    if !newValue {
                        statsManager.stopMonitoring()
                    }
                    // Note: Smart monitoring will handle starting when switching to stats tab
                }

                Defaults.Toggle(key: .enableLLMUsageFeature) {
                    Text("Enable LLM Usage Monitor")
                }
                .settingsHighlight(id: highlightID("Enable LLM Usage Monitor"))

            } header: {
                Text("General")
            } footer: {
                Text("When enabled, the Stats tab will display real-time system performance graphs. This feature requires system permissions and may use additional battery. Enabling LLM Usage Monitor adds a Usage tab that tracks token usage and spend across your configured AI providers.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if enableLLMUsageFeature {
                Section {
                    Defaults.Toggle(key: .enableClaudeProvider) {
                        Text("Claude")
                    }
                    .settingsHighlight(id: highlightID("Claude Provider"))

                    Defaults.Toggle(key: .enableCodexProvider) {
                        Text("Codex")
                    }
                    .settingsHighlight(id: highlightID("Codex Provider"))

                    Defaults.Toggle(key: .enableCursorProvider) {
                        Text("Cursor")
                    }
                    .settingsHighlight(id: highlightID("Cursor Provider"))
                } header: {
                    Text("LLM Providers")
                } footer: {
                    Text("Choose which AI providers appear in the Usage tab.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if enableStatsFeature {
                Section {
                    Defaults.Toggle(key: .statsStopWhenNotchCloses) {
                        Text("Stop monitoring after closing the notch")
                    }
                    .settingsHighlight(id: highlightID("Stop monitoring after closing the notch"))
                    .help("When enabled, stats monitoring stops a few seconds after the notch closes.")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Update interval")
                            Spacer()
                            Text(formattedUpdateInterval)
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $statsUpdateInterval, in: 1...60, step: 1)
                            .accessibilityLabel("Stats update interval")

                        Text("Controls how often system metrics refresh while monitoring is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if shouldShowStatsBatteryWarning {
                        Label {
                            Text("High-frequency updates without a timeout can increase battery usage.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                    }
                } header: {
                    Text("Monitoring Behavior")
                } footer: {
                    Text("Sampling can continue while the notch is closed when the timeout is disabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    Defaults.Toggle(key: .showCpuGraph) {
                        Text("CPU Usage")
                    }
                    .settingsHighlight(id: highlightID("CPU Usage"))

                    if showCpuGraph {
                        Picker("Temperature unit", selection: $cpuTemperatureUnit) {
                            ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                                Text(unit.localizedName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsHighlight(id: highlightID("Temperature unit"))
                    }
                    Defaults.Toggle(key: .showMemoryGraph) {
                        Text("Memory Usage")
                    }
                    .settingsHighlight(id: highlightID("Memory Usage"))
                    Defaults.Toggle(key: .showGpuGraph) {
                        Text("GPU Usage")
                    }
                    .settingsHighlight(id: highlightID("GPU Usage"))
                    Defaults.Toggle(key: .showNetworkGraph) {
                        Text("Network Activity")
                    }
                    .settingsHighlight(id: highlightID("Network Activity"))
                    Defaults.Toggle(key: .showDiskGraph) {
                        Text("Disk I/O")
                    }
                    .settingsHighlight(id: highlightID("Disk I/O"))
                } header: {
                    Text("Graph Visibility")
                } footer: {
                    if enabledGraphsCount >= 4 {
                        Text("With \(enabledGraphsCount) graphs enabled, the Dynamic Island will expand horizontally to accommodate all graphs in a single row.")
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Text("Each graph can be individually enabled or disabled. Network activity shows download/upload speeds, and disk I/O shows read/write speeds.")
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Text("Monitoring Status")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statsManager.isMonitoring ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(statsManager.isMonitoring ? "Active" : "Stopped")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if statsManager.isMonitoring {
                        if showCpuGraph {
                            HStack {
                                Text("CPU Usage")
                                Spacer()
                                Text(statsManager.cpuUsageString)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showMemoryGraph {
                            HStack {
                                Text("Memory Usage")
                                Spacer()
                                Text(statsManager.memoryUsageString)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showGpuGraph {
                            HStack {
                                Text("GPU Usage")
                                Spacer()
                                Text(statsManager.gpuUsageString)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showNetworkGraph {
                            HStack {
                                Text("Network Download")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.networkDownload))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Network Upload")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.networkUpload))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showDiskGraph {
                            HStack {
                                Text("Disk Read")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.diskRead))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Disk Write")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.diskWrite))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Text("Last Updated")
                            Spacer()
                            Text(statsManager.lastUpdated, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Live Performance Data")
                }

                Section {
                    HStack {
                        Button(statsManager.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                            if statsManager.isMonitoring {
                                statsManager.stopMonitoring()
                            } else {
                                statsManager.startMonitoring()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(statsManager.isMonitoring ? .red : .blue)

                        Spacer()

                        Button("Clear Data") {
                            statsManager.clearHistory()
                        }
                        .buttonStyle(.bordered)
                        .disabled(statsManager.isMonitoring)
                    }
                } header: {
                    Text("Controls")
                }
            }
        }
        .navigationTitle("Stats")
    }
}
