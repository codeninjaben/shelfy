import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted inside the app; keep the host inert so tests own the file system.
        guard !Self.isRunningUnitTests else { return }
        DebugOptions.applyAppearanceOverride()
        let model = AppModel()
        self.model = model
        model.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching Shelfy again (Finder, Spotlight) is the way back to Settings when the
        // menu bar icon is hidden.
        model?.openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
