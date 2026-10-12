import AppKit

/// Composition root and coordinator. Owns the shared model, the download observer and the
/// two presentation controllers, and makes sure only one basket surface is open at a time.
@MainActor
final class AppModel {
    enum Surface { case edge, popover }

    let preferences = Preferences()
    let accessibility = SystemAccessibility()
    let folder = WatchedFolder()
    let screens = ScreenDirectory()
    let collection = FileCollection(store: .standard)
    let quickLook = QuickLookController()

    private(set) var edge: EdgeController!
    private(set) var menuBar: StatusItemController!
    private var observer: DownloadObserver?
    private var settings: SettingsWindowController?
    private var observers: [NSObjectProtocol] = []
    private var maintenanceTask: Task<Void, Never>?
    private var revalidateTask: Task<Void, Never>?
    #if DEBUG
    private var debugCommands: DebugCommands?
    #endif

    private static let watermarkKey = "Shelfy.lastObservedAt"

    // MARK: Startup

    func start() {
        collection.load()
        edge = EdgeController(app: self)
        menuBar = StatusItemController(app: self)

        collection.onArrival = { [weak self] item in self?.handleArrival(item) }
        collection.onItemsChanged = { [weak self] in self?.handleItemsChanged() }
        preferences.onChange = { [weak self] key in self?.handlePreferenceChange(key) }
        folder.onChange = { [weak self] in self?.restartObserver(catchingUp: false) }
        folder.onStatusChange = { [weak self] status in self?.folderStatusChanged(status) }
        accessibility.onChange = { [weak self] in self?.edge.relayout() }

        applyPresentation()
        restartObserver(catchingUp: true)
        observeSystem()
        startMaintenance()
        #if DEBUG
        debugCommands = DebugCommands(app: self)
        #endif
        Log.app.info("Shelfy started; watching \(Log.redacted(self.folder.url.path), privacy: .public)")
    }

    func prepareForTermination() {
        observer?.stop()
        collection.saveNow()
        recordWatermark()
    }

    // MARK: Coordination

    var isPopoverShown: Bool { menuBar?.isPopoverShown ?? false }
    var isSettingsVisible: Bool { settings?.isVisible ?? false }

    /// Only one basket at a time: opening one surface closes the other.
    func surfaceWillOpen(_ surface: Surface) {
        switch surface {
        case .edge: menuBar.closePopover()
        case .popover: edge.collapse(explicit: true)
        }
    }

    func openSettings() {
        menuBar.closePopover()
        edge.collapse(explicit: true)
        let controller = settings ?? SettingsWindowController(app: self)
        settings = controller
        controller.show()
    }

    private func applyPresentation() {
        let mode = preferences.presentation
        edge.setEnabled(mode.showsEdgeTab)
        menuBar.setEnabled(mode.showsMenuBarIcon)
    }

    // MARK: Events

    private func handleArrival(_ item: BasketItem) {
        Log.app.info("Added \(Log.redacted(item.name), privacy: .public) to the basket")
        edge.playArrival()
        menuBar.playArrival()
    }

    private func handleItemsChanged() {
        edge.contentDidChange()
        menuBar.contentDidChange()
    }

    private func handlePreferenceChange(_ key: Preferences.Key) {
        switch key {
        case .presentation:
            applyPresentation()
        case .edge, .display:
            edge.collapse(explicit: true)
            edge.relayout()
            edge.updateFullScreenState()
            edge.revealTabPosition()
        case .tabVisibility, .hideTabWhenEmpty:
            edge.relayout()
            edge.revealTabPosition()
        case .verticalPosition:
            edge.relayout()
            edge.revealTabPosition(nudge: false) // keep it visible while the slider moves
        case .hoverSensitivity:
            edge.relayout()
        case .arrivalAnimation:
            break
        }
    }

    private func handleObserverEvent(_ event: DownloadObserver.Event) {
        switch event {
        case .fileReady(let url, let isCatchUp):
            // Catch-up can find files that are already in the restored basket; leave those be.
            if isCatchUp, let status = FileStatus(path: url.path),
               collection.items.contains(where: { $0.fileNumber == status.inode }) { return }
            collection.add(fileAt: url)
        case .entriesRemoved:
            scheduleRevalidation()
        case .folderUnavailable:
            folder.refreshStatus()
        }
    }

    private func folderStatusChanged(_ status: WatchedFolder.Status) {
        Log.files.info("Watched folder status: \(String(describing: status), privacy: .public)")
        if status == .available {
            restartObserver(catchingUp: false)
        } else {
            observer?.stop()
            observer = nil
        }
        collection.revalidateInBackground()
        handleItemsChanged()
    }

    // MARK: Observing the folder

    /// Starts watching on the observer's own queue. The first access may wait on the system's
    /// privacy prompt; that happens off the main thread, and a refusal comes back as
    /// `.folderUnavailable`.
    private func restartObserver(catchingUp: Bool) {
        observer?.stop()
        observer = nil
        var options = DownloadObserver.Options()
        // First launch has no watermark: start fresh rather than pulling in the whole folder.
        // Later launches pick up downloads that finished while Shelfy wasn't running.
        if catchingUp, let since = UserDefaults.standard.object(forKey: Self.watermarkKey) as? Date {
            options.catchUpSince = since
        }
        let observer = DownloadObserver(folder: folder.url, options: options) { [weak self] event in
            Task { @MainActor in self?.handleObserverEvent(event) }
        }
        self.observer = observer
        observer.start()
        recordWatermark()
        handleItemsChanged()
    }

    private func recordWatermark() {
        UserDefaults.standard.set(Date(), forKey: Self.watermarkKey)
    }

    private func scheduleRevalidation() {
        revalidateTask?.cancel()
        revalidateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.collection.revalidateInBackground()
        }
    }

    /// Periodic housekeeping: follow moved or deleted files, notice permission changes, and
    /// advance the watermark used to catch up after a relaunch.
    private func startMaintenance() {
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.recordWatermark()
                self.folder.refreshStatus() // access changes arrive through onStatusChange
                if !self.collection.items.isEmpty {
                    self.collection.revalidateInBackground()
                }
            }
        }
    }

    // MARK: System notifications

    private func observeSystem() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screens.refresh()
                self?.edge.screensDidChange()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.edge.activeSpaceDidChange() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.edge.updateFullScreenState() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // FSEvents streams survive sleep; just re-check what may have changed.
                guard let self else { return }
                self.folder.refreshStatus()
                self.collection.revalidateInBackground()
                self.edge.screensDidChange()
            }
        })
    }
}
