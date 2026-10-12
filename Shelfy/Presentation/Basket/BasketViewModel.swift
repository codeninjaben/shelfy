import AppKit
import Observation

/// The surface presenting a basket (edge panel or menu-bar popover). The view model asks it
/// to stay open, collapse, or take keyboard focus as the user interacts.
@MainActor
protocol BasketHost: AnyObject {
    func basketRequestsCollapse()
    func basketRequestsKeyFocus()
    func basketContentSizeDidChange()
    func basketDragDidBegin()
    func basketDragDidEnd(success: Bool)
    func basketQuickLookDidChange(visible: Bool)
    func basketBeginReposition()
    func basketReposition(toScreenY y: CGFloat)
    func basketEndReposition()
}

extension BasketHost {
    func basketBeginReposition() {}
    func basketReposition(toScreenY y: CGFloat) {}
    func basketEndReposition() {}
}

/// Per-surface UI state (stack vs. grid, selection) over the shared `FileCollection`.
@MainActor @Observable
final class BasketViewModel {
    enum Surface { case edge, popover }
    enum Mode { case stack, grid }

    let surface: Surface
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored weak var host: (any BasketHost)?

    var mode: Mode = .stack {
        didSet { if oldValue != mode { host?.basketContentSizeDidChange() } }
    }
    var selection: Set<UUID> = []
    /// Fixed end and moving end of a shift-click or shift-arrow range selection.
    @ObservationIgnored private var anchorID: UUID?
    @ObservationIgnored private var cursorID: UUID?
    /// Thumbnail views by item, for Quick Look's zoom transition.
    @ObservationIgnored private var sourceViews: [UUID: WeakView] = [:]
    @ObservationIgnored lazy var menuBuilder = ItemMenuBuilder(model: self)

    init(surface: Surface, app: AppModel) {
        self.surface = surface
        self.app = app
    }

    var collection: FileCollection { app.collection }
    var items: [BasketItem] { collection.items }
    var effectiveMode: Mode { items.count > 1 ? mode : .stack }

    var layout: BasketMetrics.Layout {
        if items.isEmpty || app.folder.status != .available { return .empty }
        return effectiveMode == .grid ? .grid(itemCount: items.count) : .hero
    }

    var showsFooter: Bool { !items.isEmpty || collection.canUndoClear }

    var preferredSize: CGSize {
        let width = surface == .edge ? BasketMetrics.edgeWidth : BasketMetrics.popoverWidth
        return BasketMetrics.size(for: layout, surfaceWidth: width, showsFooter: showsFooter)
    }

    var summary: String { ItemKind.summary(for: items) }

    // MARK: Collection changes

    func collectionDidChange() {
        let ids = Set(items.map(\.id))
        if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
        sourceViews = sourceViews.filter { ids.contains($0.key) && $0.value.view != nil }
    }

    /// Each fresh opening starts compact: the hero file or the stack.
    func prepareForPresentation() {
        selection.removeAll()
        if mode != .stack { mode = .stack }
    }

    // MARK: Targets

    /// Finder semantics: acting on a selected item acts on the whole selection, acting on an
    /// unselected item acts on just that item, and with nothing specified everything is in play.
    func targets(anchor id: UUID?) -> [BasketItem] {
        if let id {
            if selection.contains(id) { return items.filter { selection.contains($0.id) } }
            return items.filter { $0.id == id }
        }
        if !selection.isEmpty { return items.filter { selection.contains($0.id) } }
        return items
    }

    func dragTargets(anchor id: UUID?, role: FileDragSource.Role) -> [BasketItem] {
        switch role {
        case .stack: return items
        case .single, .cell: return targets(anchor: id).filter(\.isReadable)
        }
    }

    // MARK: Pointer

    func click(_ id: UUID?, role: FileDragSource.Role, modifiers: NSEvent.ModifierFlags) {
        host?.basketRequestsKeyFocus()
        switch role {
        case .stack:
            mode = .grid
        case .single:
            if let id { select(id) }
        case .cell:
            guard let id else { return }
            if modifiers.contains(.command) {
                if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                anchorID = id
                cursorID = id
            } else if modifiers.contains(.shift), let anchorID,
                      let from = items.firstIndex(where: { $0.id == anchorID }),
                      let to = items.firstIndex(where: { $0.id == id }) {
                selection = Set(items[min(from, to)...max(from, to)].map(\.id))
                cursorID = id
            } else {
                select(id)
            }
        }
    }

    func doubleClick(_ id: UUID?, role: FileDragSource.Role) {
        switch role {
        case .stack: mode = .grid
        case .single, .cell: open(targets(anchor: id))
        }
    }

    func dragDidBegin() { host?.basketDragDidBegin() }
    func dragDidEnd(operation: NSDragOperation) { host?.basketDragDidEnd(success: !operation.isEmpty) }

    func register(sourceView: NSView, for id: UUID) {
        sourceViews[id] = WeakView(view: sourceView)
    }

    func sourceView(for id: UUID) -> NSView? {
        sourceViews[id]?.view
    }

    // MARK: Actions

    func open(_ targets: [BasketItem]) {
        let urls = targets.filter(\.isReadable).map(\.url)
        guard !urls.isEmpty else { NSSound.beep(); return }
        FileActions.open(urls)
        host?.basketRequestsCollapse()
    }

    func open(_ item: BasketItem, withApplicationAt application: URL) {
        FileActions.open(item.url, withApplicationAt: application)
        host?.basketRequestsCollapse()
    }

    func reveal(_ targets: [BasketItem]) {
        guard !targets.isEmpty else { return }
        FileActions.reveal(targets.map(\.url))
        host?.basketRequestsCollapse()
    }

    func copy(_ targets: [BasketItem]) {
        guard !targets.isEmpty else { return }
        FileActions.copy(targets.map(\.url))
    }

    func quickLook(_ targets: [BasketItem]) {
        let previewable = targets.filter(\.isReadable)
        guard !previewable.isEmpty else { NSSound.beep(); return }
        host?.basketRequestsKeyFocus()
        app.quickLook.toggle(items: previewable, from: self)
    }

    func remove(_ targets: [BasketItem]) {
        let ids = Set(targets.map(\.id))
        guard !ids.isEmpty else { return }
        selection.subtract(ids)
        collection.remove(ids)
    }

    func clearAll() {
        selection.removeAll()
        collection.clear()
    }

    func undoClear() {
        collection.undoClear()
    }

    func toggleMode() {
        guard items.count > 1 else { return }
        mode = mode == .stack ? .grid : .stack
    }

    func openWatchedFolder() {
        NSWorkspace.shared.open(app.folder.url)
        host?.basketRequestsCollapse()
    }

    func collapse() {
        host?.basketRequestsCollapse()
    }

    // MARK: Keyboard

    /// Finder-like keys. Returns true when the event was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "a": selectAll()
            case "c": copy(targets(anchor: nil))
            case "o": open(targets(anchor: nil))
            case "r": reveal(targets(anchor: nil))
            case "y": quickLook(targets(anchor: nil))
            case "z": undoClear()
            case "w": collapse()
            case ",": app.openSettings()
            default:
                if event.keyCode == KeyCode.delete { removeSelectionOrSingle() } else { return false }
            }
            return true
        }
        switch event.keyCode {
        case KeyCode.escape:
            if app.quickLook.isVisible { app.quickLook.close() } else { collapse() }
        case KeyCode.space:
            quickLook(targets(anchor: nil))
        case KeyCode.returnKey, KeyCode.enter:
            open(targets(anchor: nil))
        case KeyCode.delete, KeyCode.forwardDelete:
            removeSelectionOrSingle()
        case KeyCode.leftArrow: moveSelection(by: -1, extending: flags.contains(.shift))
        case KeyCode.rightArrow: moveSelection(by: 1, extending: flags.contains(.shift))
        case KeyCode.upArrow: moveSelection(by: -BasketMetrics.gridColumns, extending: flags.contains(.shift))
        case KeyCode.downArrow: moveSelection(by: BasketMetrics.gridColumns, extending: flags.contains(.shift))
        default:
            return false
        }
        return true
    }

    private func selectAll() {
        guard !items.isEmpty else { return }
        if items.count > 1 { mode = .grid }
        selection = Set(items.map(\.id))
    }

    private func removeSelectionOrSingle() {
        if !selection.isEmpty {
            remove(targets(anchor: nil))
        } else if items.count == 1 {
            remove(items)
        } else {
            NSSound.beep()
        }
    }

    private func moveSelection(by delta: Int, extending: Bool) {
        guard !items.isEmpty else { return }
        if items.count > 1, mode == .stack {
            mode = .grid
            select(items[0].id)
            return
        }
        let current = cursorID.flatMap { id in items.firstIndex { $0.id == id } }
            ?? items.firstIndex { selection.contains($0.id) }
        let next = current.map { min(max($0 + delta, 0), items.count - 1) } ?? 0
        if extending, let anchorID, let from = items.firstIndex(where: { $0.id == anchorID }) {
            selection = Set(items[min(from, next)...max(from, next)].map(\.id))
            cursorID = items[next].id
        } else {
            select(items[next].id)
        }
    }

    private func select(_ id: UUID) {
        selection = [id]
        anchorID = id
        cursorID = id
    }
}

nonisolated enum KeyCode {
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

struct WeakView {
    weak var view: NSView?
}
