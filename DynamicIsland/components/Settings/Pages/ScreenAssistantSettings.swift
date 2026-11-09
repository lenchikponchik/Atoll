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

struct ScreenAssistantSettings: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @Default(.enableScreenAssistant) var enableScreenAssistant
    @Default(.screenAssistantDisplayMode) var screenAssistantDisplayMode
    @Default(.geminiApiKey) var geminiApiKey
    @State private var apiKeyText = ""
    @State private var showingApiKey = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.screenAssistant.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenAssistant) {
                    Text("Enable Screen Assistant")
                }
                .settingsHighlight(id: highlightID("Enable Screen Assistant"))
            } header: {
                Text("AI Assistant")
            } footer: {
                Text("AI-powered assistant that can analyze files, images, and provide conversational help. Use Cmd+Shift+A to quickly access the assistant.")
            }

            if enableScreenAssistant {
                Section {
                    HStack {
                        Text("Gemini API Key")
                        Spacer()
                        if geminiApiKey.isEmpty {
                            Text("Not Set")
                                .foregroundColor(.red)
                        } else {
                            Text("••••••••")
                                .foregroundColor(.green)
                        }

                        Button(showingApiKey ? "Hide" : (geminiApiKey.isEmpty ? "Set" : "Change")) {
                            if showingApiKey {
                                showingApiKey = false
                                if !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Defaults[.geminiApiKey] = apiKeyText
                                }
                                apiKeyText = ""
                            } else {
                                showingApiKey = true
                                apiKeyText = geminiApiKey
                            }
                        }
                    }

                    if showingApiKey {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Enter your Gemini API Key", text: $apiKeyText)
                                .textFieldStyle(.roundedBorder)

                            Text("Get your free API key from Google AI Studio")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Button("Open Google AI Studio") {
                                    NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                                }
                                .buttonStyle(.link)

                                Spacer()

                                Button("Save") {
                                    Defaults[.geminiApiKey] = apiKeyText
                                    showingApiKey = false
                                    apiKeyText = ""
                                }
                                .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    HStack {
                        Text("Display Mode")
                        Spacer()
                        Picker("", selection: $screenAssistantDisplayMode) {
                            ForEach(ScreenAssistantDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }
                    .settingsHighlight(id: highlightID("Display Mode"))

                    HStack {
                        Text("Attached Files")
                        Spacer()
                        Text("\(screenAssistantManager.attachedFiles.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Recording Status")
                        Spacer()
                        Text(screenAssistantManager.isRecording ? "Recording" : "Ready")
                            .foregroundColor(screenAssistantManager.isRecording ? .red : .secondary)
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    switch screenAssistantDisplayMode {
                    case .popover:
                        Text("Popover mode shows the assistant as a dropdown attached to the AI button. Panel mode shows the assistant in a floating window near the notch.")
                    case .panel:
                        Text("Panel mode shows the assistant in a floating window near the notch. Popover mode shows the assistant as a dropdown attached to the AI button.")
                    }
                }

                Section {
                    Button("Clear All Files") {
                        screenAssistantManager.clearAllFiles()
                    }
                    .foregroundColor(.red)
                    .disabled(screenAssistantManager.attachedFiles.isEmpty)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Clear all files removes all attached files and audio recordings. This action is permanent.")
                }

                if !screenAssistantManager.attachedFiles.isEmpty {
                    Section {
                        ForEach(screenAssistantManager.attachedFiles) { file in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: file.type.iconName)
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                    Text(file.type.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(timeAgoString(from: file.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(file.name)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Attached Files")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Screen Assistant")
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
