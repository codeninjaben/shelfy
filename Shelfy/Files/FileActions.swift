import AppKit

/// Workspace actions on the original files.
@MainActor
enum FileActions {
    static func open(_ urls: [URL]) {
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    static func open(_ url: URL, withApplicationAt application: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Puts file references on the clipboard, like ⌘C in Finder.
    static func copy(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    /// Applications that can open `url`, default first.
    static func applications(toOpen url: URL) -> [URL] {
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if let preferred = NSWorkspace.shared.urlForApplication(toOpen: url) {
            apps.removeAll { $0 == preferred }
            apps.insert(preferred, at: 0)
        }
        return apps
    }
}
