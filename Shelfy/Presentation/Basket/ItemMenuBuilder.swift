import AppKit

/// Builds the context menu for basket items.
@MainActor
final class ItemMenuBuilder {
    private unowned let model: BasketViewModel

    init(model: BasketViewModel) {
        self.model = model
    }

    func menu(for targets: [BasketItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard !targets.isEmpty else { return menu }
        let count = targets.count
        let model = model
        let readable = targets.allSatisfy(\.isReadable)

        menu.addItem(ClosureMenuItem(count == 1 ? "Open" : "Open \(count) Items", symbol: "arrow.up.forward.app",
                                     enabled: readable) { model.open(targets) })
        if count == 1, let item = targets.first, readable {
            menu.addItem(openWithItem(for: item))
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quick Look", symbol: "eye", enabled: readable) { model.quickLook(targets) })
        menu.addItem(ClosureMenuItem("Show in Finder", symbol: "folder") { model.reveal(targets) })
        menu.addItem(ClosureMenuItem("Copy", symbol: "doc.on.doc") { model.copy(targets) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(count == 1 ? "Remove from Shelf" : "Remove \(count) Items from Shelf",
                                     symbol: "minus.circle") { model.remove(targets) })
        return menu
    }

    private func openWithItem(for item: BasketItem) -> NSMenuItem {
        let parent = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        let submenu = NSMenu()
        let model = model
        for (index, application) in FileActions.applications(toOpen: item.url).prefix(12).enumerated() {
            var title = FileManager.default.displayName(atPath: application.path)
            if title.hasSuffix(".app") { title = String(title.dropLast(4)) }
            if index == 0 { title += " (default)" }
            let entry = ClosureMenuItem(title) { model.open(item, withApplicationAt: application) }
            let icon = NSWorkspace.shared.icon(forFile: application.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
            if index == 0 { submenu.addItem(.separator()) }
        }
        parent.submenu = submenu
        parent.isEnabled = !submenu.items.isEmpty
        return parent
    }
}

/// A menu item that runs a closure.
nonisolated final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", enabled: Bool = true,
         handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: key)
        target = self
        isEnabled = enabled
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @MainActor @objc private func runHandler() {
        handler()
    }
}
