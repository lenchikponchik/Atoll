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

/// Telegram tab: the latest messages Telegram delivered as notifications.
struct NotchTelegramView: View {
    @ObservedObject private var manager = TelegramMessagesManager.shared
    @ObservedObject private var fullDiskAccess = FullDiskAccessPermissionStore.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var scrollSuppressionToken = UUID()

    var body: some View {
        Group {
            if manager.messages.isEmpty {
                placeholder
            } else {
                messageList
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .environment(\.colorScheme, .dark)
        .onAppear { manager.refresh() }
    }

    private var messageList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 6) {
                ForEach(manager.messages) { message in
                    TelegramMessageRow(message: message) {
                        manager.openTelegram()
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        // Scrolling the list must not trigger the island's own open/close scroll gesture
        .onHover { vm.setScrollGestureSuppression($0, token: scrollSuppressionToken) }
        .onDisappear { vm.setScrollGestureSuppression(false, token: scrollSuppressionToken) }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            switch manager.state {
            case .noAccess:
                Text("Telegram messages need Full Disk Access")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                Button {
                    fullDiskAccess.requestAccessPrompt()
                } label: {
                    Text("Grant access")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            case .unavailable:
                Text("Could not read Notification Center")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(.gray)
            default:
                Text("No new Telegram messages")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(.gray)
                Text("Messages appear here when Telegram shows a notification")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TelegramMessageRow: View {
    let message: TelegramMessage
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(avatarColor.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(initials)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(message.chat)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(message.date, format: timeFormat)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    (senderPrefix + Text(message.text).foregroundStyle(.gray))
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(isHovering ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var senderPrefix: Text {
        guard let sender = message.sender else { return Text(verbatim: "") }
        return Text(verbatim: sender + ": ").foregroundStyle(.white.opacity(0.85))
    }

    private var timeFormat: Date.FormatStyle {
        Calendar.current.isDateInToday(message.date)
            ? .dateTime.hour().minute()
            : .dateTime.day().month(.abbreviated)
    }

    private var initials: String {
        let words = message.chat.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }
        return letters.isEmpty ? "T" : String(letters).uppercased()
    }

    /// Stable per-chat colour, like Telegram's placeholder avatars.
    private var avatarColor: Color {
        let palette: [Color] = [.blue, .teal, .green, .orange, .pink, .purple, .red, .indigo]
        let hash = message.chat.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}
