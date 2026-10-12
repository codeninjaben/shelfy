import AppKit
import SwiftUI

extension View {
    /// Hover tracking that works while Shelfy is inactive (the basket opens without
    /// activating the app, so ordinary key-window hover tracking would stay silent).
    func onActiveHover(_ action: @escaping (Bool) -> Void) -> some View {
        background(HoverTracker(onChange: action))
    }
}

private struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView {
        HoverTrackingView(onChange: onChange)
    }

    func updateNSView(_ view: HoverTrackingView, context: Context) {
        view.onChange = onChange
    }
}

private final class HoverTrackingView: NSView {
    var onChange: (Bool) -> Void
    private var area: NSTrackingArea?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { onChange(true) }
    override func mouseExited(with event: NSEvent) { onChange(false) }
}

/// The basket's grab handle: drag it to slide the tab and basket along the screen edge.
struct RepositionHandle: NSViewRepresentable {
    let model: BasketViewModel

    func makeNSView(context: Context) -> RepositionHandleView {
        let view = RepositionHandleView()
        view.model = model
        return view
    }

    func updateNSView(_ view: RepositionHandleView, context: Context) {
        view.model = model
    }
}

final class RepositionHandleView: NSView {
    weak var model: BasketViewModel?
    private var area: NSTrackingArea?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) {
        if !isDragging { NSCursor.openHand.set() }
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        NSCursor.closedHand.set()
        model?.host?.basketBeginReposition()
    }

    override func mouseDragged(with event: NSEvent) {
        model?.host?.basketReposition(toScreenY: NSEvent.mouseLocation.y)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        model?.host?.basketEndReposition()
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        (inside ? NSCursor.openHand : NSCursor.arrow).set()
    }
}
