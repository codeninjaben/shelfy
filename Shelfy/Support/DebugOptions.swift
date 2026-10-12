import AppKit

/// Launch-argument overrides for verifying appearance and accessibility variants without
/// changing system settings, e.g. `open Shelfy.app --args -ShelfyDebugAppearance dark`.
@MainActor
enum DebugOptions {
    static func applyAppearanceOverride() {
        switch UserDefaults.standard.string(forKey: "ShelfyDebugAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    static var forceReduceMotion: Bool { UserDefaults.standard.bool(forKey: "ShelfyDebugReduceMotion") }
    static var forceReduceTransparency: Bool { UserDefaults.standard.bool(forKey: "ShelfyDebugReduceTransparency") }
}
