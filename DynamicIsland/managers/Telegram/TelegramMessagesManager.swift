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
import SQLite3

/// One Telegram message as it appeared in Notification Center.
struct TelegramMessage: Identifiable, Equatable {
    let id: String
    let chat: String
    let sender: String?
    let text: String
    let date: Date
}

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

    nonisolated static let bundleIdentifiers = [
        "ru.keepcoder.telegram",      // Telegram for macOS (App Store / direct)
        "org.telegram.desktop",       // Telegram Desktop
        "com.tdesktop.telegram"
    ]
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
            // Keep messages already seen this session: Notification Center forgets
            // them as soon as the banner is dismissed or the chat is read
            var merged: [String: TelegramMessage] = [:]
            for message in messages { merged[message.id] = message }
            for message in fresh { merged[message.id] = message }
            let sorted = merged.values.sorted { $0.date > $1.date }
            let trimmed = Array(sorted.prefix(Self.historyLimit))
            if trimmed != messages { messages = trimmed }
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
        let path = databaseURL.path
        guard FileManager.default.isReadableFile(atPath: path) else {
            // Without Full Disk Access the group container cannot even be listed
            return FullDiskAccessAuthorization.hasPermission() ? .unavailable : .noAccess
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return .unavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        let placeholders = bundleIdentifiers.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT r.rec_id, r.data, r.delivered_date, r.request_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE LOWER(a.identifier) IN (\(placeholders))
            ORDER BY r.rec_id DESC LIMIT 40
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .unavailable
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, identifier) in bundleIdentifiers.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), identifier, -1, transient)
        }

        var result: [TelegramMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let recordID = sqlite3_column_int64(statement, 0)
            guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            let delivered = sqlite3_column_double(statement, 2)
            let requested = sqlite3_column_double(statement, 3)
            if let message = parse(data: data, recordID: recordID, fallbackDate: delivered > 0 ? delivered : requested) {
                result.append(message)
            }
        }
        return .messages(result)
    }

    /// The record payload is a binary plist: { date, req: { titl, subt, body } }.
    nonisolated private static func parse(data: Data, recordID: Int64, fallbackDate: Double) -> TelegramMessage? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }

        func text(_ key: String) -> String? {
            let value = (request[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }

        let title = text("titl")
        let subtitle = text("subt")
        guard let body = text("body") ?? subtitle else { return nil }

        let timestamp: Double
        if let date = plist["date"] as? Double, date > 0 {
            timestamp = date
        } else if let date = plist["date"] as? Date {
            timestamp = date.timeIntervalSinceReferenceDate
        } else {
            timestamp = fallbackDate
        }

        return TelegramMessage(
            id: "\(recordID)",
            chat: title ?? "Telegram",
            sender: text("body") == nil ? nil : subtitle,
            text: body,
            date: Date(timeIntervalSinceReferenceDate: timestamp)
        )
    }
}
