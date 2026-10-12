import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var previousApp: NSRunningApplication?

    init(app: AppModel) {
        let hosting = NSHostingController(rootView: SettingsView(app: app))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Shelfy Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("ShelfySettings")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
            window.center()
        }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        defer { previousApp = nil }
        // Shelfy has no other regular windows; give focus back rather than leaving it nowhere.
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
    }
}
