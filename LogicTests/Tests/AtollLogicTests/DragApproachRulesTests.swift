import XCTest
@testable import AtollLogic

final class DragApproachRulesTests: XCTestCase {
    // A 1710x1107 pt MacBook screen, origin bottom-left
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private let notchWidth: CGFloat = 200

    private var zone: CGRect {
        DragApproachRules.approachZone(screenFrame: screen, closedNotchWidth: notchWidth)
    }

    func testApproachZoneIsCentredUnderTheTopEdge() {
        XCTAssertEqual(zone.midX, screen.midX)
        XCTAssertEqual(zone.maxY, screen.maxY)
        XCTAssertEqual(zone.height, DragApproachRules.approachDepth)
        XCTAssertEqual(zone.width, notchWidth + DragApproachRules.sideMargin * 2)
    }

    // The point of the feature: the shelf opens well before the cursor hits the edge
    func testDragIsCaughtBelowTheNotchBeforeReachingTheEdge() {
        let onTheWayUp = CGPoint(x: screen.midX, y: screen.maxY - 100)
        XCTAssertTrue(DragApproachRules.contains(zone, onTheWayUp))
    }

    func testDragAtTheVeryTopEdgeStillCounts() {
        XCTAssertTrue(DragApproachRules.contains(zone, CGPoint(x: screen.midX, y: screen.maxY)))
    }

    func testDragFarBelowDoesNotOpen() {
        XCTAssertFalse(DragApproachRules.contains(zone, CGPoint(x: screen.midX, y: screen.maxY - 300)))
    }

    func testDragToTheMenuBarFarFromTheNotchDoesNotOpen() {
        XCTAssertFalse(DragApproachRules.contains(zone, CGPoint(x: 100, y: screen.maxY - 10)))
        XCTAssertFalse(DragApproachRules.contains(zone, CGPoint(x: screen.maxX - 100, y: screen.maxY - 10)))
    }

    func testZoneNeverExceedsANarrowScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 600)
        let zone = DragApproachRules.approachZone(screenFrame: narrow, closedNotchWidth: 200)
        XCTAssertEqual(zone.width, 300)
        XCTAssertEqual(zone.minX, 0)
    }

    func testZoneFollowsAScreenThatIsNotAtTheOrigin() {
        let external = CGRect(x: 1710, y: 200, width: 2560, height: 1440)
        let zone = DragApproachRules.approachZone(screenFrame: external, closedNotchWidth: 200)
        XCTAssertEqual(zone.midX, external.midX)
        XCTAssertEqual(zone.maxY, external.maxY)
        XCTAssertFalse(DragApproachRules.contains(zone, CGPoint(x: 855, y: 1100)), "a point on the other screen")
    }

    func testNearTopPreCheck() {
        XCTAssertTrue(DragApproachRules.isNearTop(CGPoint(x: 5, y: screen.maxY - 50), screenFrame: screen))
        XCTAssertFalse(DragApproachRules.isNearTop(CGPoint(x: 5, y: screen.maxY - 500), screenFrame: screen))
    }

    func testKeepOpenZoneCoversTheOpenIslandWithSlack() {
        let open = CGSize(width: 770, height: 200)
        let keep = DragApproachRules.keepOpenZone(screenFrame: screen, openNotchSize: open)
        // Inside the island
        XCTAssertTrue(DragApproachRules.contains(keep, CGPoint(x: screen.midX, y: screen.maxY - 150)))
        // Just under its bottom edge: still tolerated
        XCTAssertTrue(DragApproachRules.contains(keep, CGPoint(x: screen.midX, y: screen.maxY - 240)))
        // Clearly gone
        XCTAssertFalse(DragApproachRules.contains(keep, CGPoint(x: screen.midX, y: screen.maxY - 400)))
        XCTAssertFalse(DragApproachRules.contains(keep, CGPoint(x: 100, y: screen.maxY - 100)))
    }

    func testKeepOpenZoneContainsTheApproachZone() {
        // Otherwise the island would open and immediately count the drag as gone
        let keep = DragApproachRules.keepOpenZone(screenFrame: screen, openNotchSize: CGSize(width: 640, height: 200))
        XCTAssertTrue(keep.contains(zone))
    }
}
