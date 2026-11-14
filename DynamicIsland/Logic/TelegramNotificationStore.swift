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

import Foundation
import SQLite3

// Pure logic: no app singletons, no Defaults. Compiled into the app and into
// the LogicTests package, so keep it dependency-free.

/// One Telegram message as it appeared in Notification Center.
struct TelegramMessage: Identifiable, Equatable {
    let id: String
    let chat: String
    let sender: String?
    let text: String
    let date: Date
}

/// Reads Telegram's notifications out of the macOS Notification Center database.
enum TelegramNotificationStore {
    enum ReadResult: Equatable {
        /// The database file is not readable (missing, or no Full Disk Access).
        case unreadable
        /// The file is there but is not the database we expect.
        case unavailable
        case messages([TelegramMessage])
    }

    static let bundleIdentifiers = [
        "ru.keepcoder.telegram",      // Telegram for macOS (App Store / direct)
        "org.telegram.desktop",       // Telegram Desktop
        "com.tdesktop.telegram"
    ]

    static func read(
        databasePath path: String,
        bundleIdentifiers: [String] = TelegramNotificationStore.bundleIdentifiers,
        limit: Int = 40
    ) -> ReadResult {
        guard FileManager.default.isReadableFile(atPath: path) else { return .unreadable }
        guard !bundleIdentifiers.isEmpty else { return .messages([]) }

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
            ORDER BY r.rec_id DESC LIMIT \(max(0, limit))
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .unavailable
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, identifier) in bundleIdentifiers.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), identifier.lowercased(), -1, transient)
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
    static func parse(data: Data, recordID: Int64, fallbackDate: Double) -> TelegramMessage? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }

        func text(_ key: String) -> String? {
            let value = (request[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }

        let title = text("titl")
        let subtitle = text("subt")
        let body = text("body")
        guard let shownText = body ?? subtitle else { return nil }

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
            // With no body the subtitle is the text itself, not a sender
            sender: body == nil ? nil : subtitle,
            text: shownText,
            date: Date(timeIntervalSinceReferenceDate: timestamp)
        )
    }

    /// Keeps messages already seen (Notification Center forgets them once the banner
    /// is dismissed), newest first, capped at `limit`.
    static func merge(existing: [TelegramMessage], fresh: [TelegramMessage], limit: Int) -> [TelegramMessage] {
        var byID: [String: TelegramMessage] = [:]
        for message in existing { byID[message.id] = message }
        for message in fresh { byID[message.id] = message }
        let sorted = byID.values.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.id > rhs.id
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}
