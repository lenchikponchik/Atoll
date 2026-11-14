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

import CoreGraphics
import Foundation

// Pure logic: compiled into the app and into the LogicTests package.

/// Which standard tabs the open island shows, and in what order.
enum NotchTabKind: Equatable {
    case home
    /// The full music player; in minimalistic mode the player lives on Home instead.
    case music
    case shelf
    case timer
    case notes
    /// The notes slot showing only the clipboard (notes off, clipboard as a tab).
    case clipboard
    case ai
    case telegram
}

struct NotchTabSettings: Equatable {
    var homeVisible = true
    var musicEnabled = true
    var shelfEnabled = true
    var timerEnabled = true
    var timerShownAsTab = true
    var notesEnabled = true
    var clipboardShownAsTab = false
    var aiEnabled = true
    var aiProviderAvailable = true
    var telegramEnabled = true

    var visibleTabs: [NotchTabKind] {
        var tabs: [NotchTabKind] = []
        if homeVisible { tabs.append(.home) }
        if musicEnabled { tabs.append(.music) }
        if shelfEnabled { tabs.append(.shelf) }
        if timerEnabled && timerShownAsTab { tabs.append(.timer) }
        if notesEnabled {
            tabs.append(.notes)
        } else if clipboardShownAsTab {
            tabs.append(.clipboard)
        }
        // AI usage sits where the terminal used to be; hidden when no AI tool is installed
        if aiEnabled && aiProviderAvailable { tabs.append(.ai) }
        // Telegram took the place of the removed system load (Stats) tab
        if telegramEnabled { tabs.append(.telegram) }
        return tabs
    }
}

enum NotchSizingRules {
    /// Minimum open-island width that keeps the tab row clear of the physical notch.
    static func recommendedMinimumWidth(forTabCount count: Int) -> CGFloat {
        if count >= 6 { return 770 }
        if count >= 5 { return 690 }
        return 640
    }

    /// The stored width, raised to the minimum and capped at what the screen allows.
    static func clampedWidth(stored: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(stored, minimum), maximum)
    }
}
