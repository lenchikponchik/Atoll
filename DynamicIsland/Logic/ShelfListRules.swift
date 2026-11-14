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

enum ShelfListRules {
    /// Appends `new` to `existing`, skipping anything whose key is already present
    /// (also within `new` itself). Existing order is preserved.
    static func mergeUnique<Item, Key: Hashable>(
        existing: [Item],
        new: [Item],
        key: (Item) -> Key
    ) -> (merged: [Item], added: [Item]) {
        var merged = existing
        var seen = Set(existing.map(key))
        var added: [Item] = []
        for item in new where seen.insert(key(item)).inserted {
            merged.append(item)
            added.append(item)
        }
        return (merged, added)
    }

    /// Removes exactly the items found invalid. Items added to `current` while the
    /// validation was running are kept: they were never checked.
    static func removingInvalid<Item, ID: Hashable>(
        from current: [Item],
        invalidIDs: Set<ID>,
        id: (Item) -> ID
    ) -> [Item] {
        current.filter { !invalidIDs.contains(id($0)) }
    }
}
