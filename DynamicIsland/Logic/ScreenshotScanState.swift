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

// Pure logic: compiled into the app and into the LogicTests package.

/// Remembers which files of the screenshot folder were already offered to the shelf.
struct ScreenshotScanState: Equatable {
    private(set) var knownFiles: Set<String> = []

    init(knownFiles: Set<String> = []) {
        self.knownFiles = knownFiles
    }

    /// Marks files as already offered without putting them on the shelf.
    mutating func markKnown<S: Sequence>(_ names: S) where S.Element == String {
        knownFiles.formUnion(names)
    }

    /// Call with the folder's current contents. Returns the names that are new and
    /// must go on the shelf, forgets names that are no longer on disk.
    ///
    /// A screenshot dragged out of the shelf stays known until its file is really
    /// gone: it lingers on disk for a few seconds and must not be offered again.
    mutating func newFiles(inFolder present: [String]) -> [String] {
        knownFiles.formIntersection(present)
        var seen = Set<String>()
        let fresh = present.filter { !knownFiles.contains($0) && seen.insert($0).inserted }
        knownFiles.formUnion(fresh)
        return fresh
    }

    mutating func reset() {
        knownFiles.removeAll()
    }
}
