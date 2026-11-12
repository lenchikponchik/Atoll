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

/// Redirects system screenshots into a private folder and puts every new
/// screenshot on the shelf. Screenshots dragged out of the shelf are removed
/// from the shelf and deleted from disk.
@MainActor
final class ScreenshotShelfService {
    static let shared = ScreenshotShelfService()

    // screencaptureui silently falls back to the Desktop for folders inside ~/Library
    static let directory: URL = FileManager.default
        .urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Atoll Screenshots", isDirectory: true)

    private static let screencaptureDomain = "com.apple.screencapture" as CFString
    private static let legacyLocationKey = "location" as CFString
    // macOS 27 reads the screenshot folder from this key and ignores the legacy one
    private static let screenshotLocationKey = "location-screenshot" as CFString
    // Drop targets may still be reading the file right after the drag ends
    private static let deletionDelay: TimeInterval = 10

    private var source: DispatchSourceFileSystemObject?
    private var knownFiles: Set<String> = []
    private var cancellable: AnyCancellable?

    private init() {}

    func start() {
        guard cancellable == nil else { return }
        cancellable = Defaults.publisher(keys: .screenshotsToShelf, .dynamicShelf)
            .sink { _ in
                Task { @MainActor in
                    ScreenshotShelfService.shared.apply(enabled: Defaults[.screenshotsToShelf] && Defaults[.dynamicShelf])
                }
            }
    }

    func isScreenshot(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(Self.directory.standardizedFileURL.path + "/")
    }

    /// Any file macOS marked as a screen capture, wherever it lives now
    /// (e.g. a screenshot dragged to the Desktop and back onto the shelf).
    private func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// Removes dragged screenshots from the shelf; files from our folder are also deleted.
    /// `sourceURLs` are the item locations captured when the drag began: a move drop
    /// (e.g. into Finder) relocates the file and its bookmark follows it.
    /// Returns the dragged items that are not screenshots.
    func consumeDraggedScreenshots(_ items: [ShelfItem], sourceURLs: [ShelfItem.ID: URL]) -> [ShelfItem] {
        guard Defaults[.screenshotsToShelf] else { return items }
        var remaining: [ShelfItem] = []
        for item in items {
            guard let url = sourceURLs[item.id] else {
                remaining.append(item)
                continue
            }
            if isScreenshot(url) {
                ShelfStateViewModel.shared.remove(item)
                knownFiles.remove(url.lastPathComponent)
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.deletionDelay) {
                    try? FileManager.default.removeItem(at: url)
                }
            } else if isScreenCapture(url) {
                // The file lives outside our folder: keep it, just take it off the shelf
                ShelfStateViewModel.shared.remove(item)
            } else {
                remaining.append(item)
            }
        }
        return remaining
    }

    // MARK: - Enable / disable

    private func apply(enabled: Bool) {
        if enabled {
            redirectSystemScreenshots()
            startWatching()
        } else {
            stopWatching()
            restoreSystemScreenshots()
        }
    }

    private func storedLocation(for key: CFString) -> String? {
        CFPreferencesCopyAppValue(key, Self.screencaptureDomain) as? String
    }

    private func currentScreenshotLocation() -> String? {
        storedLocation(for: Self.screenshotLocationKey) ?? storedLocation(for: Self.legacyLocationKey)
    }

    private func pointsToOurDirectory(_ location: String?) -> Bool {
        guard let location else { return false }
        let path = URL(fileURLWithPath: (location as NSString).expandingTildeInPath).standardizedFileURL.path
        return path == Self.directory.standardizedFileURL.path
    }

    private func redirectSystemScreenshots() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let current = currentScreenshotLocation()
        if !pointsToOurDirectory(current) {
            Defaults[.screenshotShelfPreviousLocation] = current ?? ""
        }
        let alreadyRedirected = pointsToOurDirectory(storedLocation(for: Self.screenshotLocationKey))
            && pointsToOurDirectory(storedLocation(for: Self.legacyLocationKey))
        guard !alreadyRedirected else { return }
        setScreenshotLocation(Self.directory.path)
    }

    private func restoreSystemScreenshots() {
        guard pointsToOurDirectory(currentScreenshotLocation()) else { return }
        let previous = Defaults[.screenshotShelfPreviousLocation]
        setScreenshotLocation(previous.isEmpty ? nil : previous)
        Defaults[.screenshotShelfPreviousLocation] = ""
    }

    private func setScreenshotLocation(_ path: String?) {
        CFPreferencesSetAppValue(Self.screenshotLocationKey, path as CFString?, Self.screencaptureDomain)
        CFPreferencesSetAppValue(Self.legacyLocationKey, path as CFString?, Self.screencaptureDomain)
        CFPreferencesAppSynchronize(Self.screencaptureDomain)
        // SystemUIServer caches the screenshot location on older macOS versions
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["SystemUIServer"]
        try? process.run()
    }

    // MARK: - Folder watching

    private func startWatching() {
        guard source == nil else { return }
        let fd = open(Self.directory.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("⚠️ ScreenshotShelfService: cannot watch \(Self.directory.path)")
            return
        }

        knownFiles = Set(ShelfStateViewModel.shared.items.compactMap { item -> String? in
            guard case let .file(bookmark) = item.kind,
                  let url = Bookmark(data: bookmark).resolveURL(),
                  isScreenshot(url) else { return nil }
            return url.lastPathComponent
        })

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler {
            Task { @MainActor in ScreenshotShelfService.shared.scan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source

        // Pick up screenshots taken while Atoll was not running. Older files were already
        // offered (and may have been removed from the shelf); treat them as known so a
        // relaunch or reboot does not put every leftover file back on the shelf.
        markFilesKnown(createdBefore: Defaults[.screenshotShelfLastScanDate] ?? Date())
        scan()
    }

    private func markFilesKnown(createdBefore cutoff: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let created, created > cutoff { continue }
            knownFiles.insert(file.lastPathComponent)
        }
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
        knownFiles.removeAll()
    }

    private func scan() {
        // macOS writes screenshots to a hidden file first and renames it when done
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        Defaults[.screenshotShelfLastScanDate] = Date()

        let names = Set(files.map(\.lastPathComponent))
        knownFiles.formIntersection(names)

        let newFiles = files.filter { !knownFiles.contains($0.lastPathComponent) }
        guard !newFiles.isEmpty else { return }
        knownFiles.formUnion(newFiles.map(\.lastPathComponent))

        Task {
            let items = await ShelfDropService.items(from: newFiles)
            ShelfStateViewModel.shared.add(items)
        }
    }
}
