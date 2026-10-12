import AppKit
import ColorSync
import Observation

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Stable across reconnects and reboots, unlike `CGDirectDisplayID`.
    var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The frame in Core Graphics window-server coordinates (origin at the top left of the
    /// primary display), as used by `CGWindowListCopyWindowInfo`.
    var quartzFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

/// The connected displays, for the Settings picker.
@MainActor @Observable
final class ScreenDirectory {
    struct Display: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private(set) var displays: [Display] = []

    init() { refresh() }

    func refresh() {
        let current = NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { Display(id: $0, name: screen.localizedName) }
        }
        if current != displays { displays = current }
    }

    func isConnected(_ id: String?) -> Bool {
        guard let id else { return true }
        return displays.contains { $0.id == id }
    }
}
