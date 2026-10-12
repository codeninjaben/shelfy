import AppKit
import Quartz
import SwiftUI

/// The menu-bar icon and its popover, which shows the same basket as the edge tab.
/// Left-click toggles the popover; right-click (or Control-click) shows a short menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    let basket: BasketViewModel
    private unowned let app: AppModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// The app that was frontmost before the popover took focus; it gets focus back on close.
    private var previousApp: NSRunningApplication?

    init(app: AppModel) {
        self.app = app
        basket = BasketViewModel(surface: .popover, app: app)
        super.init()
        basket.host = self
    }

    var isPopoverShown: Bool { popover?.isShown ?? false }

    func setEnabled(_ enabled: Bool) {
        if enabled, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "ShelfyStatusItem"
            if let button = item.button {
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.setAccessibilityLabel("Shelfy")
            }
            statusItem = item
            refresh()
        } else if !enabled, let item = statusItem {
            closePopover()
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Updates the icon: filled while there are files the user hasn't looked at yet.
    func refresh() {
        guard let button = statusItem?.button else { return }
        let collection = app.collection
        let symbol = collection.hasUnseen ? "tray.and.arrow.down.fill" : "tray.and.arrow.down"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Shelfy")
        image?.isTemplate = true
        button.image = image
        let summary = collection.items.isEmpty ? "No files" : ItemKind.summary(for: collection.items)
        button.toolTip = collection.items.isEmpty ? "Shelfy" : "Shelfy — \(summary)"
        button.setAccessibilityValue(collection.hasUnseen ? "\(summary), \(collection.unseen.count) new" : summary)
    }

    func contentDidChange() {
        basket.collectionDidChange()
        refresh()
    }

    func playArrival() {
        refresh()
        if isPopoverShown { markSeenSoon() }
    }

    // MARK: Popover

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        isPopoverShown ? closePopover() : showPopover()
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        app.surfaceWillOpen(.popover)
        app.folder.refreshStatus()
        app.collection.revalidateInBackground()
        basket.prepareForPresentation()
        let popover = self.popover ?? makePopover()
        popover.animates = !app.accessibility.reduceMotion
        // The user clicked the menu bar deliberately, so the popover may take keyboard focus.
        // Remember who had it so it can go back when the popover closes.
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            previousApp = front
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        markSeenSoon()
    }

    func closePopover() {
        guard let popover, popover.isShown else { return }
        popover.performClose(nil)
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let controller = PopoverHostingController(
            rootView: PopoverRootContent(basket: basket, accessibility: app.accessibility))
        controller.basket = basket
        controller.quickLook = app.quickLook
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        self.popover = popover
        return popover
    }

    private func markSeenSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.isPopoverShown else { return }
            self.app.collection.markAllSeen()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        basket.selection.removeAll()
        if app.quickLook.isVisible { app.quickLook.close() }
        restoreFocus()
    }

    private func restoreFocus() {
        defer { previousApp = nil }
        // Only hand focus back if Shelfy still has it and nothing else of Shelfy's (Settings) needs it.
        guard NSApp.isActive, !app.isSettingsVisible else { return }
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        } else {
            NSApp.hide(nil)
        }
    }

    // MARK: Menu

    private func showMenu() {
        guard let button = statusItem?.button else { return }
        closePopover()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem("Open Shelf", symbol: "tray") { [weak self] in self?.showPopover() })
        menu.addItem(ClosureMenuItem("Clear Shelf", symbol: "xmark.circle",
                                     enabled: !app.collection.items.isEmpty) { [weak self] in
            self?.app.collection.clear()
        })
        menu.addItem(ClosureMenuItem("Open \(app.folder.displayName)", symbol: "folder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.app.folder.url)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", symbol: "gearshape", key: ",") { [weak self] in
            self?.app.openSettings()
        })
        menu.addItem(ClosureMenuItem("Quit Shelfy", symbol: "power", key: "q") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 6), in: button)
    }
}

// MARK: - BasketHost

extension StatusItemController: BasketHost {
    func basketRequestsCollapse() {
        closePopover()
    }

    func basketRequestsKeyFocus() {
        popover?.contentViewController?.view.window?.makeKey()
    }

    func basketContentSizeDidChange() {
        // The hosting controller publishes the new preferred size; NSPopover animates to it.
    }

    func basketDragDidBegin() {}

    func basketDragDidEnd(success: Bool) {
        guard success else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.closePopover()
        }
    }

    func basketQuickLookDidChange(visible: Bool) {
        // Keep the transient popover from closing while Quick Look holds focus.
        popover?.behavior = visible ? .applicationDefined : .transient
    }
}

// MARK: - Hosting

struct PopoverRootContent: View {
    let basket: BasketViewModel
    let accessibility: SystemAccessibility

    var body: some View {
        let size = basket.preferredSize
        BasketView(model: basket, chrome: .popover)
            .frame(width: size.width, height: size.height)
            .environment(accessibility)
    }
}

final class PopoverHostingController: NSHostingController<PopoverRootContent> {
    weak var basket: BasketViewModel?
    weak var quickLook: QuickLookController?

    override func keyDown(with event: NSEvent) {
        if basket?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.beginControl(panel) }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.endControl(panel) }
    }
}
