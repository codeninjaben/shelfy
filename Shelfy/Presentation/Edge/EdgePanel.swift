import AppKit
import Quartz
import SwiftUI

/// A borderless, non-activating panel. It floats above other windows on every Space
/// (including full-screen ones), never activates Shelfy when it appears, and only becomes key
/// when the user clicks inside the open basket.
final class EdgePanel: NSPanel {
    weak var controller: EdgeController?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 20, height: 80),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Receive events across the whole (small) frame, including the transparent
        // activation margin around the tab.
        ignoresMouseEvents = false
        setAccessibilityRole(.popover)
        setAccessibilityLabel("Shelfy")
    }

    override var canBecomeKey: Bool { controller?.isExpanded ?? false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard let controller else { return super.sendEvent(event) }
        if controller.interceptsTabEvents, controller.handleTabEvent(event) {
            return
        }
        // Keyboard focus moves to the basket only when the user deliberately clicks it.
        if (event.type == .leftMouseDown || event.type == .rightMouseDown), controller.isExpanded, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

    override func becomeKey() {
        super.becomeKey()
        controller?.panelDidBecomeKey()
    }

    override func resignKey() {
        super.resignKey()
        controller?.panelDidResignKey()
    }

    // MARK: Quick Look

    // AppKit declares these on NSObject without isolation; Quick Look calls them on the main thread.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { controller?.quickLook.beginControl(panel) }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { controller?.quickLook.endControl(panel) }
    }
}

/// The panel's content view: hosts the SwiftUI surface and tracks the pointer in a few
/// small regions of the panel, never anywhere else on screen.
final class EdgeRootView: NSView {
    enum Region: Int {
        /// The edge band that summons a hidden tab.
        case reveal
        /// The tab and its activation margin.
        case tab
        /// The open basket plus a little slack.
        case basket
    }

    weak var controller: EdgeController?
    private var areas: [NSTrackingArea] = []

    /// Tracked regions in this view's coordinates.
    var regions: [Region: CGRect] = [:] {
        didSet {
            if regions != oldValue { updateTrackingAreas() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        areas.forEach(removeTrackingArea)
        areas = regions.compactMap { region, rect in
            guard !rect.isEmpty else { return nil }
            let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self,
                                      userInfo: ["region": region.rawValue])
            addTrackingArea(area)
            return area
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let region = region(of: event) else { return }
        controller?.pointerEntered(region)
    }

    override func mouseExited(with event: NSEvent) {
        guard let region = region(of: event) else { return }
        controller?.pointerExited(region)
    }

    private func region(of event: NSEvent) -> Region? {
        (event.trackingArea?.userInfo?["region"] as? Int).flatMap(Region.init)
    }
}

/// Hosting view that routes unhandled keys to the basket and takes the first click.
final class EdgeHostingView: NSHostingView<EdgeSurfaceView> {
    var keyHandler: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.isKeyWindow == true, event.modifierFlags.contains(.command), keyHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
