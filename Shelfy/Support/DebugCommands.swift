#if DEBUG
import AppKit

/// Debug builds only: lets scripts drive Shelfy into specific states for screenshots and
/// verification without synthesizing mouse input. Post a distributed notification named
/// `com.benbreslow.Shelfy.debug.<command>` (sandboxed apps receive no userInfo, so the
/// command is part of the name).
@MainActor
final class DebugCommands {
    private unowned let app: AppModel
    private var observers: [NSObjectProtocol] = []

    init(app: AppModel) {
        self.app = app
        let commands: [String: @MainActor @Sendable (AppModel) -> Void] = [
            "expand": { $0.edge.expand(reason: .accessibility) },
            "hover": { $0.edge.expand(reason: .hover) },
            "collapse": { $0.edge.collapse(explicit: false) },
            "grid": { $0.edge.basket.toggleMode() },
            "select-first": { model in
                if let first = model.collection.items.first { model.edge.basket.selection = [first.id] }
            },
            "popover": { $0.menuBar.togglePopover() },
            "settings": { $0.openSettings() },
            "close-settings": { _ in NSApp.windows.first { $0.title == "Shelfy Settings" }?.close() },
            "arrival": { $0.edge.playArrival() },
            "rearm-approach": { $0.edge.rearmApproachTracking(reason: "debug command") },
            "clear": { $0.collection.clear() },
            "quicklook": { model in
                model.edge.basket.quickLook(model.edge.basket.targets(anchor: nil))
            },
        ]
        let center = DistributedNotificationCenter.default()
        for (name, action) in commands {
            observers.append(center.addObserver(forName: Notification.Name("com.benbreslow.Shelfy.debug.\(name)"),
                                                object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Log.app.debug("Debug command: \(name, privacy: .public)")
                    action(self.app)
                }
            })
        }
    }
}
#endif
