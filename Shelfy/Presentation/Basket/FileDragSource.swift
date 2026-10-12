import AppKit
import SwiftUI

/// An AppKit overlay that turns a thumbnail into a real file drag source.
///
/// Dragging writes the original files' URLs to the drag pasteboard, one dragging item per
/// file, so Finder, Mail, browser upload fields and other apps receive real files. The
/// overlay also handles clicks, double-clicks and the context menu, and accepts the first
/// mouse so a drag can start straight from the hover-revealed (non-key) basket.
struct FileDragSource: NSViewRepresentable {
    enum Role { case single, stack, cell }

    let model: BasketViewModel
    let anchorID: UUID?
    let role: Role
    var onHover: ((Bool) -> Void)?

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        configure(view)
        return view
    }

    func updateNSView(_ view: FileDragSourceView, context: Context) {
        configure(view)
    }

    private func configure(_ view: FileDragSourceView) {
        view.model = model
        view.anchorID = anchorID
        view.role = role
        view.onHover = onHover
        if let anchorID { model.register(sourceView: view, for: anchorID) }
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    weak var model: BasketViewModel?
    var anchorID: UUID?
    var role: FileDragSource.Role = .single
    var onHover: ((Bool) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var hoverArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        didStartDrag = false
        mouseDownEvent = event
        if event.clickCount == 2 {
            mouseDownEvent = nil
            model?.doubleClick(anchorID, role: role)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, !didStartDrag, let model else { return }
        let distance = hypot(event.locationInWindow.x - down.locationInWindow.x,
                             event.locationInWindow.y - down.locationInWindow.y)
        guard distance >= 3 else { return }
        didStartDrag = true
        let targets = model.dragTargets(anchor: anchorID, role: role)
        guard !targets.isEmpty else { NSSound.beep(); return }
        let session = beginDraggingSession(with: draggingItems(for: targets), event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .default
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil, !didStartDrag, event.clickCount <= 1 else { return }
        model?.click(anchorID, role: role, modifiers: event.modifierFlags)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        if let anchorID, !model.selection.contains(anchorID), role != .stack {
            model.selection = [anchorID]
        }
        let targets = role == .stack ? model.items : model.targets(anchor: anchorID)
        return model.menuBuilder.menu(for: targets)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy semantics: the original stays in the watched folder. Nothing can be dropped
        // back onto Shelfy itself.
        context == .outsideApplication ? .copy : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        model?.dragDidBegin()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model?.dragDidEnd(operation: operation)
    }

    // MARK: Drag images

    private func draggingItems(for targets: [BasketItem]) -> [NSDraggingItem] {
        let base = imageFrame()
        return targets.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let image = ThumbnailProvider.shared.bestAvailableImage(for: item).image
            let step = CGFloat(min(index, 5)) * 5
            let frame = Self.aspectFit(image.size, in: base).offsetBy(dx: step, dy: step)
            draggingItem.setDraggingFrame(frame, contents: image)
            return draggingItem
        }
    }

    private func imageFrame() -> CGRect {
        switch role {
        case .single:
            let side = min(BasketMetrics.heroSide, bounds.width, bounds.height)
            return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        case .stack:
            let side = BasketMetrics.stackSide
            return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        case .cell:
            let side = BasketMetrics.gridThumbnailSide
            return CGRect(x: bounds.midX - side / 2, y: 8, width: side, height: side)
        }
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}
