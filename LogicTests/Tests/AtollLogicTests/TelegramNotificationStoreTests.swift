import SQLite3
import XCTest
@testable import AtollLogic

final class TelegramNotificationStoreTests: XCTestCase {

    // MARK: - Parsing (TG-1, TG-2)

    private func record(_ request: [String: Any]?, date: Any? = 800_000_000.0) throws -> Data {
        var plist: [String: Any] = ["app": "ru.keepcoder.Telegram"]
        if let request { plist["req"] = request }
        if let date { plist["date"] = date }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    func testParsesTitleSubtitleBodyAndDate() throws {
        let data = try record(["titl": "Рабочий чат", "subt": "Анна", "body": "Привет!"])
        let message = try XCTUnwrap(TelegramNotificationStore.parse(data: data, recordID: 42, fallbackDate: 1))
        XCTAssertEqual(message.id, "42")
        XCTAssertEqual(message.chat, "Рабочий чат")
        XCTAssertEqual(message.sender, "Анна")
        XCTAssertEqual(message.text, "Привет!")
        XCTAssertEqual(message.date, Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    func testPrivateChatHasNoSender() throws {
        let data = try record(["titl": "Анна", "body": "Привет!"])
        let message = try XCTUnwrap(TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 1))
        XCTAssertNil(message.sender)
    }

    func testSubtitleBecomesTextWhenBodyIsMissing() throws {
        let data = try record(["titl": "Анна", "subt": "Фотография"])
        let message = try XCTUnwrap(TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 1))
        XCTAssertEqual(message.text, "Фотография")
        XCTAssertNil(message.sender, "the subtitle is the text here, not a sender")
    }

    func testMissingTitleFallsBackToAppName() throws {
        let data = try record(["body": "Привет!"])
        XCTAssertEqual(TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 1)?.chat, "Telegram")
    }

    func testWhitespaceOnlyFieldsCountAsMissing() throws {
        let data = try record(["titl": "  ", "subt": "\n", "body": "   "])
        XCTAssertNil(TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 1))
    }

    func testTextIsTrimmed() throws {
        let data = try record(["titl": " Анна ", "body": "\n Привет \n"])
        let message = try XCTUnwrap(TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 1))
        XCTAssertEqual(message.chat, "Анна")
        XCTAssertEqual(message.text, "Привет")
    }

    func testDateStoredAsDateObject() throws {
        let stored = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let data = try record(["body": "x"], date: stored)
        XCTAssertEqual(TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 1)?.date, stored)
    }

    func testMissingDateUsesFallback() throws {
        let data = try record(["body": "x"], date: nil)
        XCTAssertEqual(
            TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 123)?.date,
            Date(timeIntervalSinceReferenceDate: 123)
        )
    }

    func testRecordWithoutRequestIsSkipped() throws {
        XCTAssertNil(TelegramNotificationStore.parse(data: try record(nil), recordID: 1, fallbackDate: 1))
    }

    func testNonStringBodyIsSkipped() throws {
        let data = try record(["titl": "Анна", "body": 5])
        XCTAssertNil(TelegramNotificationStore.parse(data: data, recordID: 1, fallbackDate: 1))
    }

    func testGarbageDataIsSkipped() {
        XCTAssertNil(TelegramNotificationStore.parse(data: Data([0, 1, 2, 3]), recordID: 1, fallbackDate: 1))
        XCTAssertNil(TelegramNotificationStore.parse(data: Data(), recordID: 1, fallbackDate: 1))
    }

    // MARK: - Database (TG-3)

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-logic-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Builds a database with the same tables Notification Center uses.
    private func makeDatabase(
        _ rows: [(app: String, body: String?, delivered: Double)],
        createTables: Bool = true
    ) throws -> String {
        let path = directory.appendingPathComponent("db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        guard createTables else {
            XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE other (x INTEGER)", nil, nil, nil), SQLITE_OK)
            return path
        }
        let schema = """
            CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR, badge INTEGER NULL);
            CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB,
                request_date REAL, request_last_date REAL, delivered_date REAL, presented Bool,
                style INTEGER, snooze_fire_date REAL);
            """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

        var appIDs: [String: Int64] = [:]
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            if appIDs[row.app] == nil {
                var statement: OpaquePointer?
                sqlite3_prepare_v2(db, "INSERT INTO app (identifier) VALUES (?)", -1, &statement, nil)
                sqlite3_bind_text(statement, 1, row.app, -1, transient)
                XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
                sqlite3_finalize(statement)
                appIDs[row.app] = sqlite3_last_insert_rowid(db)
            }
            let data = row.body.map { try? record(["titl": "Чат", "body": $0], date: nil) } ?? Data([9, 9, 9])
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO record (app_id, data, delivered_date, request_date) VALUES (?, ?, ?, ?)", -1, &statement, nil)
            sqlite3_bind_int64(statement, 1, appIDs[row.app]!)
            _ = data!.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
            sqlite3_bind_double(statement, 3, row.delivered)
            sqlite3_bind_double(statement, 4, row.delivered - 1)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
        return path
    }

    private func messages(_ result: TelegramNotificationStore.ReadResult, file: StaticString = #filePath, line: UInt = #line) -> [TelegramMessage] {
        guard case .messages(let messages) = result else {
            XCTFail("expected messages, got \(result)", file: file, line: line)
            return []
        }
        return messages
    }

    func testReadsOnlyTelegramRecordsNewestFirst() throws {
        let path = try makeDatabase([
            ("ru.keepcoder.Telegram", "первое", 100),
            ("com.apple.mail", "письмо", 200),
            ("ru.keepcoder.Telegram", "второе", 300)
        ])
        let result = messages(TelegramNotificationStore.read(databasePath: path))
        XCTAssertEqual(result.map(\.text), ["второе", "первое"])
        XCTAssertEqual(result.first?.date, Date(timeIntervalSinceReferenceDate: 300))
    }

    func testIdentifierMatchIgnoresCase() throws {
        let path = try makeDatabase([("RU.KeepCoder.Telegram", "привет", 100)])
        XCTAssertEqual(messages(TelegramNotificationStore.read(databasePath: path)).count, 1)
    }

    func testTelegramDesktopIsRead() throws {
        let path = try makeDatabase([("org.telegram.desktop", "привет", 100)])
        XCTAssertEqual(messages(TelegramNotificationStore.read(databasePath: path)).count, 1)
    }

    func testLimitKeepsNewest() throws {
        let rows = (1...10).map { (app: "ru.keepcoder.telegram", body: Optional("m\($0)"), delivered: Double($0)) }
        let path = try makeDatabase(rows)
        let result = messages(TelegramNotificationStore.read(databasePath: path, limit: 3))
        XCTAssertEqual(result.map(\.text), ["m10", "m9", "m8"])
    }

    func testUnparsableRecordsAreSkippedNotFatal() throws {
        let path = try makeDatabase([
            ("ru.keepcoder.telegram", nil, 100),
            ("ru.keepcoder.telegram", "нормальное", 200)
        ])
        XCTAssertEqual(messages(TelegramNotificationStore.read(databasePath: path)).map(\.text), ["нормальное"])
    }

    func testNoTelegramRecordsGivesEmptyList() throws {
        let path = try makeDatabase([("com.apple.mail", "письмо", 100)])
        XCTAssertEqual(TelegramNotificationStore.read(databasePath: path), .messages([]))
    }

    func testMissingFileIsUnreadable() {
        let path = directory.appendingPathComponent("nope").path
        XCTAssertEqual(TelegramNotificationStore.read(databasePath: path), .unreadable)
    }

    func testDatabaseWithoutExpectedTablesIsUnavailable() throws {
        let path = try makeDatabase([], createTables: false)
        XCTAssertEqual(TelegramNotificationStore.read(databasePath: path), .unavailable)
    }

    func testFileThatIsNotADatabaseIsUnavailable() throws {
        let path = directory.appendingPathComponent("db").path
        try Data("not a database at all, just text".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(TelegramNotificationStore.read(databasePath: path), .unavailable)
    }

    // MARK: - Merging (TG-5)

    private func message(_ id: String, at time: Double, text: String = "x") -> TelegramMessage {
        TelegramMessage(id: id, chat: "Чат", sender: nil, text: text, date: Date(timeIntervalSinceReferenceDate: time))
    }

    func testMergeKeepsMessagesThatLeftNotificationCenter() {
        let merged = TelegramNotificationStore.merge(
            existing: [message("1", at: 10)],
            fresh: [message("2", at: 20)],
            limit: 40
        )
        XCTAssertEqual(merged.map(\.id), ["2", "1"])
    }

    func testMergeDoesNotDuplicateAndPrefersFreshCopy() {
        let merged = TelegramNotificationStore.merge(
            existing: [message("1", at: 10, text: "старый")],
            fresh: [message("1", at: 10, text: "новый")],
            limit: 40
        )
        XCTAssertEqual(merged.map(\.text), ["новый"])
    }

    func testMergeCapsAtLimitDroppingOldest() {
        let existing = (1...5).map { message("\($0)", at: Double($0)) }
        let merged = TelegramNotificationStore.merge(existing: existing, fresh: [message("6", at: 6)], limit: 3)
        XCTAssertEqual(merged.map(\.id), ["6", "5", "4"])
    }

    func testMergeOrderIsStableForEqualDates() {
        let merged = TelegramNotificationStore.merge(
            existing: [message("1", at: 10), message("2", at: 10)],
            fresh: [],
            limit: 40
        )
        XCTAssertEqual(merged.map(\.id), ["2", "1"])
    }
}
