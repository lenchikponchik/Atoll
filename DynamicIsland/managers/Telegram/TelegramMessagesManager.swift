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
import Combine
import Defaults
import Foundation

/// Shows the latest Telegram messages by reading the notifications Telegram posted
/// to Notification Center (needs Full Disk Access; nothing is sent anywhere and
/// Telegram itself is never touched). Event-driven: the database is re-read only
/// when macOS writes to it.
@MainActor
final class TelegramMessagesManager: ObservableObject {
    static let shared = TelegramMessagesManager()

    enum State: Equatable {
        case idle
        case ready
        case noAccess
        case unavailable
    }

    @Published private(set) var messages: [TelegramMessage] = []
    @Published private(set) var state: State = .idle

    private static let historyLimit = 40

    nonisolated private static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    private var source: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?
    private var cancellable: AnyCancellable?
    private let queue = DispatchQueue(label: "atoll.telegram.notifications", qos: .utility)

    private init() {}

    func start() {
        guard cancellable == nil else { return }
        cancellable = Defaults.publisher(.enableTelegramFeature)
            .sink { change in
                Task { @MainActor in
                    if change.newValue {
                        TelegramMessagesManager.shared.startWatching()
                    } else {
                        TelegramMessagesManager.shared.stopWatching()
                    }
                }
            }
    }

    /// Called when the tab appears: picks up access granted after launch.
    func refresh() {
        guard Defaults[.enableTelegramFeature] else { return }
        if source == nil { startWatching() } else { reload() }
    }

    func openTelegram() {
        for identifier in ["ru.keepcoder.Telegram", "org.telegram.desktop", "com.tdesktop.Telegram"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }

    // MARK: - Watching

    private func startWatching() {
        reload()
        guard source == nil else { return }
        // Notification Center appends to the write-ahead log on every change
        let walPath = Self.databaseURL.path + "-wal"
        let fd = open(walPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let events = self.source?.data ?? []
                if events.contains(.delete) || events.contains(.rename) {
                    // The log was replaced: re-attach to the new file
                    self.stopWatching(clear: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard Defaults[.enableTelegramFeature] else { return }
                        self?.startWatching()
                    }
                } else {
                    self.scheduleReload()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func stopWatching(clear: Bool = true) {
        source?.cancel()
        source = nil
        reloadWork?.cancel()
        if clear {
            messages = []
            state = .idle
        }
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func reload() {
        queue.async {
            let result = Self.readNotifications()
            Task { @MainActor in
                TelegramMessagesManager.shared.apply(result)
            }
        }
    }

    private func apply(_ result: ReadResult) {
        guard Defaults[.enableTelegramFeature] else { return }
        switch result {
        case .noAccess:
            if messages.isEmpty { state = .noAccess }
        case .unavailable:
            if messages.isEmpty { state = .unavailable }
        case .messages(let fresh):
            let merged = TelegramNotificationStore.merge(existing: messages, fresh: fresh, limit: Self.historyLimit)
            if merged != messages { messages = merged }
            if state != .ready { state = .ready }
        }
    }

    // MARK: - Database

    private enum ReadResult {
        case noAccess
        case unavailable
        case messages([TelegramMessage])
    }

    nonisolated private static func readNotifications() -> ReadResult {
        switch TelegramNotificationStore.read(databasePath: databaseURL.path) {
        case .unreadable:
            // Without Full Disk Access the group container cannot even be listed
            return FullDiskAccessAuthorization.hasPermission() ? .unavailable : .noAccess
        case .unavailable:
            return .unavailable
        case .messages(let messages):
            return .messages(messages)
        }
    }
}
