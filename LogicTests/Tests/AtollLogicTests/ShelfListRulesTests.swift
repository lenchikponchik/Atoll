import XCTest
@testable import AtollLogic

final class ShelfListRulesTests: XCTestCase {
    private struct Item: Equatable {
        let id: Int
        let key: String
    }

    // SHELF-5
    func testSameFileIsNotAddedTwice() {
        let existing = [Item(id: 1, key: "/a")]
        let result = ShelfListRules.mergeUnique(existing: existing, new: [Item(id: 2, key: "/a")]) { $0.key }
        XCTAssertEqual(result.merged, existing)
        XCTAssertEqual(result.added, [])
    }

    func testNewFilesAreAppendedInOrder() {
        let result = ShelfListRules.mergeUnique(
            existing: [Item(id: 1, key: "/a")],
            new: [Item(id: 2, key: "/c"), Item(id: 3, key: "/b")]
        ) { $0.key }
        XCTAssertEqual(result.merged.map(\.id), [1, 2, 3])
        XCTAssertEqual(result.added.map(\.id), [2, 3])
    }

    func testDuplicatesInsideOneDropCollapse() {
        let result = ShelfListRules.mergeUnique(
            existing: [Item](),
            new: [Item(id: 1, key: "/a"), Item(id: 2, key: "/a")]
        ) { $0.key }
        XCTAssertEqual(result.merged.map(\.id), [1])
    }

    func testEmptyDropChangesNothing() {
        let existing = [Item(id: 1, key: "/a")]
        let result = ShelfListRules.mergeUnique(existing: existing, new: []) { $0.key }
        XCTAssertEqual(result.merged, existing)
        XCTAssertTrue(result.added.isEmpty)
    }

    // SHELF-9: regression. Validation used to write back a stale snapshot, wiping
    // files dropped while it was running.
    func testCleanupKeepsItemsAddedDuringValidation() {
        // Validation checked items 1 and 2 and found 2 missing; item 3 arrived meanwhile.
        let current = [Item(id: 1, key: "/a"), Item(id: 2, key: "/b"), Item(id: 3, key: "/c")]
        let result = ShelfListRules.removingInvalid(from: current, invalidIDs: [2]) { $0.id }
        XCTAssertEqual(result.map(\.id), [1, 3])
    }

    func testCleanupWithNothingInvalidKeepsAll() {
        let current = [Item(id: 1, key: "/a")]
        XCTAssertEqual(ShelfListRules.removingInvalid(from: current, invalidIDs: Set<Int>()) { $0.id }, current)
    }

    func testCleanupIgnoresIDsThatAreAlreadyGone() {
        let current = [Item(id: 1, key: "/a")]
        XCTAssertEqual(ShelfListRules.removingInvalid(from: current, invalidIDs: [7]) { $0.id }, current)
    }
}
