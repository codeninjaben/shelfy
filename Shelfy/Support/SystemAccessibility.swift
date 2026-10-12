import AppKit
import Observation

/// Mirrors the system's motion and transparency preferences so both SwiftUI views and the
/// AppKit animation code read the same values.
@MainActor @Observable
final class SystemAccessibility {
    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        let motion = workspace.accessibilityDisplayShouldReduceMotion || DebugOptions.forceReduceMotion
        let transparency = workspace.accessibilityDisplayShouldReduceTransparency || DebugOptions.forceReduceTransparency
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        guard motion != reduceMotion || transparency != reduceTransparency || contrast != increaseContrast else { return }
        reduceMotion = motion
        reduceTransparency = transparency
        increaseContrast = contrast
        onChange?()
    }
}
