import XCTest
@testable import AtollLogic

final class NotchTabRulesTests: XCTestCase {

    // TAB-1
    func testDefaultOrder() {
        XCTAssertEqual(NotchTabSettings().visibleTabs, [.home, .shelf, .timer, .notes, .ai, .telegram])
    }

    func testEachFeatureTogglesOnlyItsOwnTab() {
        let all = NotchTabSettings().visibleTabs
        let cases: [(WritableKeyPath<NotchTabSettings, Bool>, NotchTabKind)] = [
            (\.homeVisible, .home),
            (\.shelfEnabled, .shelf),
            (\.timerEnabled, .timer),
            (\.notesEnabled, .notes),
            (\.aiEnabled, .ai),
            (\.telegramEnabled, .telegram)
        ]
        for (keyPath, tab) in cases {
            var settings = NotchTabSettings()
            settings[keyPath: keyPath] = false
            XCTAssertEqual(settings.visibleTabs, all.filter { $0 != tab }, "turning off \(tab)")
        }
    }

    func testTimerInPopoverModeHasNoTab() {
        var settings = NotchTabSettings()
        settings.timerShownAsTab = false
        XCTAssertFalse(settings.visibleTabs.contains(.timer))
    }

    func testClipboardTakesNotesSlotOnlyWhenNotesAreOff() {
        var settings = NotchTabSettings()
        settings.clipboardShownAsTab = true
        XCTAssertTrue(settings.visibleTabs.contains(.notes))
        XCTAssertFalse(settings.visibleTabs.contains(.clipboard))

        settings.notesEnabled = false
        XCTAssertEqual(settings.visibleTabs, [.home, .shelf, .timer, .clipboard, .ai, .telegram])

        settings.clipboardShownAsTab = false
        XCTAssertFalse(settings.visibleTabs.contains(.clipboard))
    }

    // AI-2
    func testAITabNeedsAnInstalledProvider() {
        var settings = NotchTabSettings()
        settings.aiProviderAvailable = false
        XCTAssertFalse(settings.visibleTabs.contains(.ai))
    }

    func testEverythingOffGivesNoTabs() {
        let settings = NotchTabSettings(
            homeVisible: false, shelfEnabled: false, timerEnabled: false, timerShownAsTab: false,
            notesEnabled: false, clipboardShownAsTab: false, aiEnabled: false,
            aiProviderAvailable: false, telegramEnabled: false
        )
        XCTAssertEqual(settings.visibleTabs, [])
    }

    // TAB-7: there is no way to describe a Stats tab any more
    func testNoSettingProducesMoreThanTheSixKnownTabs() {
        XCTAssertEqual(NotchTabSettings().visibleTabs.count, 6)
    }

    // OPEN-6
    func testMinimumWidthSteps() {
        XCTAssertEqual(NotchSizingRules.recommendedMinimumWidth(forTabCount: 0), 640)
        XCTAssertEqual(NotchSizingRules.recommendedMinimumWidth(forTabCount: 4), 640)
        XCTAssertEqual(NotchSizingRules.recommendedMinimumWidth(forTabCount: 5), 690)
        XCTAssertEqual(NotchSizingRules.recommendedMinimumWidth(forTabCount: 6), 770)
        XCTAssertEqual(NotchSizingRules.recommendedMinimumWidth(forTabCount: 9), 770)
    }

    func testWidthIsRaisedToMinimum() {
        XCTAssertEqual(NotchSizingRules.clampedWidth(stored: 500, minimum: 690, maximum: 1400), 690)
    }

    func testWidthInsideRangeIsKept() {
        XCTAssertEqual(NotchSizingRules.clampedWidth(stored: 800, minimum: 690, maximum: 1400), 800)
    }

    func testNarrowScreenWinsOverMinimum() {
        // The island must never be wider than the display, even below the tab minimum
        XCTAssertEqual(NotchSizingRules.clampedWidth(stored: 800, minimum: 770, maximum: 700), 700)
    }
}
