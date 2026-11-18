import AppKit
import Combine
import IslandCore
import SwiftUI

@MainActor
final class IslandController {
    private let model: IslandModel
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isHovering = false

    init(model: IslandModel) {
        self.model = model
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: IslandRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }

        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
        model.$pinned
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinned in
                guard let self, !pinned else { return }
                let inside = self.currentShapeRect.contains(NSEvent.mouseLocation)
                self.isHovering = inside
                if !inside {
                    self.collapseWork?.cancel()
                    if self.model.expanded { self.model.expanded = false }
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
        relayout()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private var currentShapeRect: CGRect {
        IslandGeometry.shapeRect(mode: model.mode, notch: model.notch, rowCount: model.rows.count, in: panel.frame, usage: model.usageLayout)
    }

    private func handleMouseMoved() {
        guard panel.isVisible else { return }
        let inside = currentShapeRect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        guard inside != isHovering else { return }
        isHovering = inside
        hover(inside)
    }

    private func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            model.expanded = true
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.model.pinned else { return }
                self.model.expanded = false
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    private var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }

    private func relayout() {
        guard model.showIsland, !model.live.isEmpty, let screen = notchScreen else {
            collapseWork?.cancel()
            isHovering = false
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            return
        }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let notch = CGSize(width: screen.frame.width - left - right, height: screen.safeAreaInsets.top)
        if model.notch != notch { model.notch = notch }

        let size = IslandGeometry.panelSize(notch: notch, rowCount: model.rows.count, usage: model.openUsageLayout)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.ignoresMouseEvents = !currentShapeRect.contains(NSEvent.mouseLocation)
        panel.orderFrontRegardless()
    }
}
