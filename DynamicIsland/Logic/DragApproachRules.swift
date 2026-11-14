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

/// Geometry for opening the island before a dragged file reaches the top screen edge.
///
/// macOS enters Mission Control when a drag is pushed against the top edge, and the
/// notch sits exactly there. Opening the shelf while the cursor is still on its way
/// gives the user a large drop target well below the edge.
/// All rects use AppKit screen coordinates (origin bottom-left).
enum DragApproachRules {
    /// How far below the top edge the approach zone reaches.
    static let approachDepth: CGFloat = 130
    /// How far the zone extends to each side of the closed notch.
    static let sideMargin: CGFloat = 150
    /// Slack around the open island before a drag counts as having left it.
    static let leaveMargin: CGFloat = 60

    /// The zone around the closed notch that opens the shelf when a drag enters it.
    static func approachZone(screenFrame: CGRect, closedNotchWidth: CGFloat) -> CGRect {
        let width = min(closedNotchWidth + sideMargin * 2, screenFrame.width)
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - approachDepth,
            width: width,
            height: approachDepth
        )
    }

    /// The open island's frame plus slack; a drag outside it has moved away.
    static func keepOpenZone(screenFrame: CGRect, openNotchSize: CGSize) -> CGRect {
        let width = min(openNotchSize.width + leaveMargin * 2, screenFrame.width)
        let height = openNotchSize.height + leaveMargin
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Cheap pre-check so the drag pasteboard is only queried near the top of the screen.
    static func isNearTop(_ point: CGPoint, screenFrame: CGRect) -> Bool {
        point.y >= screenFrame.maxY - approachDepth && point.y <= screenFrame.maxY + 1
    }

    /// Screen edges count as inside: the cursor is clamped to them during a drag.
    static func contains(_ zone: CGRect, _ point: CGPoint) -> Bool {
        point.x >= zone.minX && point.x <= zone.maxX && point.y >= zone.minY && point.y <= zone.maxY + 1
    }
}
