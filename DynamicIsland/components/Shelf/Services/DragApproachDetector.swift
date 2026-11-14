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
import Defaults
import SwiftUI

/// Opens the shelf as soon as a dragged file approaches the notch, instead of
/// waiting for the drag to touch it.
///
/// The notch is at the very top of the screen, and pushing a drag against the top
/// edge makes macOS enter Mission Control: the island then opened on top of the
/// Spaces bar and stuttered. With the island already open, the drop target is a
/// large area the cursor reaches before the edge.
@MainActor
final class DragApproachDetector {
    static let shared = DragApproachDetector()

    private var monitors: [Any] = []
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var changeCountAtMouseDown = 0
    private var contentDragActive = false
    /// The island this detector opened for the current drag, if any.
    private weak var openedViewModel: DynamicIslandViewModel?
    private var openedScreenFrame: CGRect = .zero

    private static let acceptedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .tiff, .png]

    private init() {}

    func start() {
        guard monitors.isEmpty else { return }
        // Global monitors see drags that start in other apps (Finder, browsers);
        // drags out of the shelf itself are local and deliberately not observed.
        let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            Task { @MainActor in DragApproachDetector.shared.mouseDown() }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { _ in
            Task { @MainActor in DragApproachDetector.shared.mouseDragged() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
            Task { @MainActor in DragApproachDetector.shared.mouseUp() }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    private func mouseDown() {
        changeCountAtMouseDown = dragPasteboard.changeCount
        contentDragActive = false
        openedViewModel = nil
    }

    private func mouseDragged() {
        let location = NSEvent.mouseLocation

        if let vm = openedViewModel {
            // Opened by us and the drag wandered off without entering the island
            let keepOpen = DragApproachRules.keepOpenZone(screenFrame: openedScreenFrame, openNotchSize: vm.notchSize)
            if !DragApproachRules.contains(keepOpen, location) {
                closeIfIdle(vm)
            }
            return
        }

        guard Defaults[.dynamicShelf], !Defaults[.enableMinimalisticUI] else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: 0, dy: -1).contains(location) }),
              DragApproachRules.isNearTop(location, screenFrame: screen.frame) else { return }

        // Only now ask the pasteboard: this runs for every drag event near the top
        if !contentDragActive {
            guard dragPasteboard.changeCount != changeCountAtMouseDown,
                  dragPasteboard.availableType(from: Self.acceptedTypes) != nil else { return }
            contentDragActive = true
        }

        guard let vm = viewModel(for: screen), vm.notchState == .closed,
              !LockScreenManager.shared.isLocked,
              !ShelfSelectionModel.shared.isDragging else { return }

        let zone = DragApproachRules.approachZone(screenFrame: screen.frame, closedNotchWidth: vm.closedNotchSize.width)
        guard DragApproachRules.contains(zone, location) else { return }

        DynamicIslandViewCoordinator.shared.currentView = .shelf
        withAnimation(.bouncy.speed(1.2)) {
            vm.open()
        }
        openedViewModel = vm
        openedScreenFrame = screen.frame
    }

    private func mouseUp() {
        defer {
            contentDragActive = false
            openedViewModel = nil
        }
        guard let vm = openedViewModel else { return }
        // Dropped somewhere else: do not leave the island hanging open
        let keepOpen = DragApproachRules.keepOpenZone(screenFrame: openedScreenFrame, openNotchSize: vm.notchSize)
        if !DragApproachRules.contains(keepOpen, NSEvent.mouseLocation) {
            closeIfIdle(vm)
        }
    }

    private func closeIfIdle(_ vm: DynamicIslandViewModel) {
        openedViewModel = nil
        guard vm.notchState == .open, !vm.anyDropZoneTargeting, !vm.dropEvent else { return }
        withAnimation(.smooth) {
            vm.close()
        }
    }

    private func viewModel(for screen: NSScreen) -> DynamicIslandViewModel? {
        guard let delegate = AppDelegate.shared else { return nil }
        if Defaults[.showOnAllDisplays] {
            return delegate.viewModels[screen]
        }
        return screen.localizedName == DynamicIslandViewCoordinator.shared.selectedScreen ? delegate.vm : nil
    }
}
