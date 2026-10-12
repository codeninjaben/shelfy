import AppKit

/// Detects whether a display is currently showing a full-screen app.
///
/// A full-screen window covers the display's entire frame, including the menu bar area,
/// which regular (even zoomed) windows never do. Window bounds and layers are available
/// without Screen Recording permission.
@MainActor
enum FullScreenMonitor {
    static func isShowingFullScreenApp(on screen: NSScreen) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        let target = screen.quartzFrame
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { continue }
            if abs(bounds.minX - target.minX) < 1, abs(bounds.minY - target.minY) < 1,
               abs(bounds.width - target.width) < 1, abs(bounds.height - target.height) < 1 {
                return true
            }
        }
        return false
    }
}
