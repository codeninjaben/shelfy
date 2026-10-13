import AppKit
import SwiftUI

/// Owns the edge panel: whether the tab is showing, when the basket opens and closes, and
/// what keeps it open.
///
/// Collapsed, the panel is only as big as the tab plus a small activation margin, or, while
/// the tab waits out of sight, a thin strip along the edge beside it. Pointer tracking never
/// leaves those regions. Expanding grows the panel to fit the basket first, then morphs the
/// glass surface out of the tab. Collapsing does the reverse.
@MainActor
final class EdgeController: NSObject {
    enum Phase { case hidden, collapsed, expanded, collapsing }
    enum Reason { case hover, click, accessibility }
    /// Reasons the basket must stay open even when the pointer is elsewhere.
    enum Hold: Hashable { case drag, menu, quickLook, keyFocus, reposition }

    static let tabSize = CGSize(width: 9, height: 64)
    static let dismissDelay: Duration = .milliseconds(350)
    /// How long a revealed tab lingers after the pointer leaves the edge.
    static let tabHideDelay: Duration = .milliseconds(450)

    let state = EdgeState()
    let basket: BasketViewModel
    var quickLook: QuickLookController { app.quickLook }

    private unowned let app: AppModel
    private var panel: EdgePanel?
    private var rootView: EdgeRootView?
    private var hostingView: EdgeHostingView?
    private(set) var phase: Phase = .hidden
    private var geometry: EdgeGeometry?
    private var holds: Set<Hold> = []
    private var suppressHoverUntilExit = false
    private var isFullScreenSpace = false
    /// The pointer is in the edge band around the tab.
    private var isPointerNearEdge = false
    /// The tab is briefly showing itself (new download, settings change, launch).
    private var isPeeking = false
    private var tabPress: (startY: CGFloat, isRepositioning: Bool)?
    private var repositionStart: (mouseY: CGFloat, centerY: CGFloat)?
    private var hoverTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var seenTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var hideTabTask: Task<Void, Never>?
    private var revealWatchTask: Task<Void, Never>?
    private var approachEndTask: Task<Void, Never>?
    private var approachWatchTask: Task<Void, Never>?
    private var menuObservers: [NSObjectProtocol] = []
    /// Watches for a pointer heading toward the tucked tab.
    private let approach = ApproachTracker()
    private var isPointerApproaching = false
    private var lastApproachDecision: Bool?

    init(app: AppModel) {
        self.app = app
        basket = BasketViewModel(surface: .edge, app: app)
        super.init()
        basket.host = self
        approach.onChange = { [weak self] isApproaching in self?.approachChanged(isApproaching) }
        observeMenuTracking()
    }

    var isExpanded: Bool { phase == .expanded }
    var interceptsTabEvents: Bool { phase == .collapsed }

    // MARK: Lifecycle

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard phase == .hidden else { return relayout() }
            if panel == nil { makePanel() }
            phase = .collapsed
            state.isTabHidden = tabAutoHides
            relayout()
            updateFullScreenState()
            // Show where the tab lives, then let it settle into its resting state.
            if !tabIsUnwanted { peek(for: .seconds(2.5)) }
        } else {
            guard phase != .hidden else { return }
            collapseImmediately()
            cancelTabPresenceWork()
            panel?.orderOut(nil)
            phase = .hidden
            updateApproachTracking()
        }
    }

    private func makePanel() {
        let panel = EdgePanel()
        panel.controller = self
        let root = EdgeRootView(frame: CGRect(origin: .zero, size: panel.frame.size))
        root.controller = self
        let hosting = EdgeHostingView(rootView: EdgeSurfaceView(
            state: state, basket: basket, accessibility: app.accessibility,
            onActivate: { [weak self] in self?.expand(reason: .accessibility) }))
        hosting.sizingOptions = []
        hosting.keyHandler = { [weak self] event in self?.basket.handleKey(event) ?? false }
        hosting.frame = root.bounds
        hosting.autoresizingMask = [.width, .height]
        root.addSubview(hosting)
        panel.contentView = root
        self.panel = panel
        rootView = root
        hostingView = hosting
    }

    // MARK: Layout

    /// Recomputes geometry from the current display and preferences.
    func relayout() {
        guard phase != .hidden, let geometry = computeGeometry() else { return }
        self.geometry = geometry
        state.edge = geometry.input.edge
        state.tabRect = geometry.tabRect
        switch phase {
        case .expanded:
            state.basketRect = geometry.basketRect
            setPanelFrame(geometry.expandedFrame)
        case .collapsed:
            state.basketRect = geometry.basketRect
            applyTabPresence()
        case .collapsing, .hidden:
            break // finishCollapse applies the final frame
        }
    }

    func screensDidChange() {
        collapseImmediately()
        relayout()
        updateFullScreenState()
    }

    func activeSpaceDidChange() {
        if phase == .expanded { collapse(explicit: false) }
        Task { [weak self] in
            // Let the Space transition finish before looking for full-screen windows.
            try? await Task.sleep(for: .milliseconds(450))
            self?.updateFullScreenState()
        }
    }

    /// Shows the tab for a moment after a settings change so the user can see where it went.
    func revealTabPosition(nudge: Bool = true) {
        peek(for: .seconds(2.5), nudge: nudge)
    }

    private func computeGeometry() -> EdgeGeometry? {
        guard let screen = targetScreen() else { return nil }
        let preferences = app.preferences
        return EdgeGeometry(.init(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            edge: preferences.edge,
            position: preferences.verticalPosition,
            tabSize: Self.tabSize,
            activationDepth: preferences.hoverSensitivity.activationDepth,
            basketSize: basket.preferredSize))
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let id = app.preferences.displayID, let match = screens.first(where: { $0.displayUUID == id }) {
            return match
        }
        return screens.first // the display with the menu bar
    }

    /// Resizes the panel and updates the SwiftUI coordinate space in the same pass, so the
    /// surface keeps its on-screen position while the window changes size underneath it.
    private func setPanelFrame(_ frame: CGRect) {
        guard let panel else { return }
        state.windowFrame = frame
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        updateTrackingRegions()
    }

    private func updateTrackingRegions() {
        guard let rootView, let geometry else { return }
        let window = state.windowFrame
        let bounds = CGRect(origin: .zero, size: window.size)
        func local(_ rect: CGRect) -> CGRect {
            rect.offsetBy(dx: -window.minX, dy: -window.minY).intersection(bounds)
        }
        switch phase {
        case .collapsed:
            if !tabAutoHides {
                rootView.regions = [.tab: bounds]
            } else if state.isTabHidden {
                rootView.regions = [.reveal: bounds]
            } else {
                rootView.regions = [.reveal: bounds, .tab: local(geometry.collapsedFrame)]
            }
        case .expanded, .collapsing:
            rootView.regions = [.basket: local(geometry.hoverRegion)]
        case .hidden:
            rootView.regions = [:]
        }
    }

    // MARK: Tab presence

    /// The tab waits out of sight until the pointer reaches the edge: by preference, or
    /// over a full-screen app.
    private var tabAutoHides: Bool {
        app.preferences.tabVisibility == .nearPointer || isFullScreenSpace
    }

    /// With "Hide When Empty", an empty basket takes Shelfy off the edge entirely.
    private var tabIsUnwanted: Bool {
        app.preferences.hideTabWhenEmpty && app.collection.items.isEmpty
            && !app.collection.canUndo && !isPeeking
    }

    private var tabShouldShow: Bool {
        !tabAutoHides || isPointerNearEdge || isPointerApproaching || isPeeking
            || tabPress != nil || repositionStart != nil
    }

    /// Puts the collapsed tab in its current state: off the edge, waiting as an invisible
    /// sensor strip, or visible.
    private func applyTabPresence() {
        guard phase == .collapsed, let panel, let geometry else { return }
        defer { updateApproachTracking() }
        if tabIsUnwanted {
            cancelHover()
            isPointerNearEdge = false
            state.isHoveringTab = false
            state.isTabHidden = true
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }

        if tabShouldShow {
            hideTabTask?.cancel()
            setPanelFrame(tabAutoHides ? geometry.revealedFrame : geometry.collapsedFrame)
            if state.isTabHidden {
                withAnimation(app.accessibility.reduceMotion ? .easeOut(duration: 0.15)
                                                             : .spring(response: 0.32, dampingFraction: 0.74)) {
                    state.isTabHidden = false
                }
                updateTrackingRegions()
            }
        } else if !state.isTabHidden {
            cancelHover()
            withAnimation(.easeIn(duration: 0.2), completionCriteria: .logicallyComplete) {
                state.isTabHidden = true
                state.isHoveringTab = false
            } completion: { [weak self] in
                guard let self, self.phase == .collapsed, self.state.isTabHidden, !self.tabShouldShow,
                      let geometry = self.geometry else { return }
                self.setPanelFrame(geometry.sensorFrame)
            }
        } else {
            setPanelFrame(geometry.sensorFrame)
        }
    }

    /// Shows the tab for a while: a new download, a settings change, or launch.
    func peek(for duration: Duration, nudge: Bool = false) {
        guard phase == .collapsed else { return }
        isPeeking = true
        applyTabPresence()
        if nudge { state.arrivalPulse &+= 1 }
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.isPeeking = false
            self.applyTabPresence()
        }
    }

    private func pointerNearEdgeChanged(_ isNear: Bool) {
        guard phase == .collapsed else { return }
        hideTabTask?.cancel()
        if isNear {
            isPointerNearEdge = true
            applyTabPresence()
            watchReveal()
            // The tab may have slid out right under a resting pointer; no enter event follows.
            if let geometry, geometry.collapsedFrame.contains(NSEvent.mouseLocation) { pointerEnteredTab() }
        } else {
            hideTabTask = Task { [weak self] in
                try? await Task.sleep(for: Self.tabHideDelay)
                guard !Task.isCancelled, let self, self.phase == .collapsed else { return }
                self.isPointerNearEdge = false
                self.applyTabPresence()
            }
        }
    }

    /// A safety net for a missed exit event while the tab is revealed.
    private func watchReveal() {
        revealWatchTask?.cancel()
        revealWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, self.phase == .collapsed, self.isPointerNearEdge, let geometry = self.geometry else { return }
                if !geometry.revealedFrame.contains(NSEvent.mouseLocation) {
                    self.isPointerNearEdge = false
                    self.applyTabPresence()
                    return
                }
            }
        }
    }

    private func cancelTabPresenceWork() {
        peekTask?.cancel()
        hideTabTask?.cancel()
        revealWatchTask?.cancel()
        isPeeking = false
        endApproach()
    }

    // MARK: Approach

    /// Approach tracking runs only while the tab is tucked and on screen.
    private func updateApproachTracking() {
        if let geometry {
            approach.configure(
                target: ApproachModel.Target(edge: geometry.input.edge, edgeX: geometry.edgeX,
                                             tabMinY: geometry.tabRect.minY, tabMaxY: geometry.tabRect.maxY),
                tuning: app.preferences.hoverSensitivity.approachTuning)
        }
        let shouldRun = phase == .collapsed && geometry != nil && (panel?.isVisible ?? false)
        if shouldRun != lastApproachDecision {
            lastApproachDecision = shouldRun
            Log.edge.info("Approach tracking wanted: \(shouldRun, privacy: .public) (phase \(String(describing: self.phase), privacy: .public), tab on screen \(self.panel?.isVisible ?? false, privacy: .public))")
        }
        approach.setRunning(shouldRun)
        if !shouldRun, isPointerApproaching {
            isPointerApproaching = false
            state.isApproaching = false
        }
    }

    private func approachChanged(_ isApproaching: Bool) {
        guard phase == .collapsed else { return }
        approachEndTask?.cancel()
        if isApproaching {
            setApproaching(true)
        } else {
            // A short grace period, so a wobble at the zone's border doesn't flicker the tab.
            approachEndTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, !self.approach.isApproaching else { return }
                self.setApproaching(false)
            }
        }
    }

    /// Sticks the tab out (revealing it if it was tucked away) without ever opening the basket.
    private func setApproaching(_ isApproaching: Bool) {
        guard isPointerApproaching != isApproaching else { return }
        isPointerApproaching = isApproaching
        Log.edge.info("Pointer \(isApproaching ? "approaching" : "no longer approaching", privacy: .public) the tab")
        withAnimation(app.accessibility.reduceMotion ? .easeOut(duration: 0.15)
                                                     : .spring(response: 0.3, dampingFraction: 0.76)) {
            state.isApproaching = isApproaching
        }
        applyTabPresence()
        if isApproaching { watchApproach() }
    }

    /// Lets the tab settle back if the pointer stops short of it.
    private func watchApproach() {
        approachWatchTask?.cancel()
        approachWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.phase == .collapsed, self.isPointerApproaching else { return }
                let idle = ProcessInfo.processInfo.systemUptime - self.approach.lastActivity
                let atTab = self.geometry?.revealedFrame.contains(NSEvent.mouseLocation) ?? false
                if idle > 1.2, !atTab {
                    self.approach.reset()
                    self.setApproaching(false)
                    return
                }
            }
        }
    }

    /// Reinstalls the pointer monitors (for verification; wake and unlock do this on their own).
    func rearmApproachTracking(reason: String) {
        approach.rearm(reason: reason)
    }

    private func endApproach() {
        approachEndTask?.cancel()
        approachWatchTask?.cancel()
        approach.reset()
        isPointerApproaching = false
        state.isApproaching = false
    }

    // MARK: Expanding and collapsing

    func expand(reason: Reason) {
        switch phase {
        case .expanded:
            if reason != .hover { focusPanel() }
            return
        case .hidden:
            return
        case .collapsed, .collapsing:
            break
        }
        cancelHover()
        hideTabTask?.cancel()
        endApproach()
        let wasCollapsing = phase == .collapsing
        app.surfaceWillOpen(.edge)
        app.folder.refreshStatus()
        app.collection.revalidateInBackground()
        if !wasCollapsing { basket.prepareForPresentation() }
        guard let geometry = computeGeometry() else { return }
        self.geometry = geometry
        state.tabRect = geometry.tabRect
        phase = .expanded
        updateApproachTracking() // not needed while the basket is open
        if let panel, !panel.isVisible { panel.orderFrontRegardless() }
        setPanelFrame(geometry.expandedFrame)

        let reduceMotion = app.accessibility.reduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.82)) {
            state.basketRect = geometry.basketRect
            state.isExpanded = true
            state.isHoveringTab = false
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .easeOut(duration: 0.22).delay(0.07)) {
            state.showsContent = true
        }
        if reason != .hover { focusPanel() }
        startWatchdog()
        scheduleSeen()
        Log.edge.debug("Expanded (\(String(describing: reason), privacy: .public))")
    }

    /// - Parameter explicit: The user asked for it (button, Escape, a completed action), so
    ///   the tab won't reopen until the pointer has left it.
    func collapse(explicit: Bool = false) {
        guard phase == .expanded else { return }
        phase = .collapsing
        cancelPendingWork()
        if app.quickLook.isVisible { app.quickLook.close() }
        holds.removeAll()
        if explicit { suppressHoverUntilExit = true }
        resignFocus()
        updateTrackingRegions()

        // When the tab is meant to wait out of sight, shrink straight back into the edge.
        let pointerNearTab = geometry?.revealedFrame.contains(NSEvent.mouseLocation) ?? false
        let tucksAway = tabAutoHides && !pointerNearTab && !isPeeking
        let reduceMotion = app.accessibility.reduceMotion
        withAnimation(.easeIn(duration: 0.1)) {
            state.showsContent = false
        }
        withAnimation(reduceMotion ? .easeIn(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.92),
                      completionCriteria: .logicallyComplete) {
            state.isExpanded = false
            if tucksAway { state.isTabHidden = true }
        } completion: { [weak self] in
            self?.finishCollapse()
        }
    }

    private func collapseImmediately() {
        guard phase == .expanded || phase == .collapsing else { return }
        cancelPendingWork()
        holds.removeAll()
        resignFocus()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.isExpanded = false
            state.showsContent = false
        }
        phase = .collapsing
        finishCollapse()
    }

    private func finishCollapse() {
        guard phase == .collapsing else { return }
        phase = .collapsed
        basket.selection.removeAll()
        if let geometry = computeGeometry() {
            self.geometry = geometry
            state.tabRect = geometry.tabRect
            state.basketRect = geometry.basketRect
        }
        let pointer = NSEvent.mouseLocation
        isPointerNearEdge = tabAutoHides && (geometry?.revealedFrame.contains(pointer) ?? false)
        applyTabPresence()
        if isPointerNearEdge { watchReveal() }
        if geometry?.collapsedFrame.contains(pointer) == true {
            if !suppressHoverUntilExit { pointerEnteredTab() } // still resting on the tab: a fresh hover
        } else {
            suppressHoverUntilExit = false
        }
        Log.edge.debug("Collapsed")
    }

    private func focusPanel() {
        guard let panel, phase == .expanded else { return }
        panel.makeKey()
        if let hostingView { panel.makeFirstResponder(hostingView) }
    }

    /// Hands keyboard focus back to the app the user was in. Shelfy never activated, so
    /// cycling the panel out and back returns key status to that app's window.
    private func resignFocus() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Pointer

    func pointerEntered(_ region: EdgeRootView.Region) {
        switch region {
        case .reveal: pointerNearEdgeChanged(true)
        case .tab: pointerEnteredTab()
        case .basket: pointerEnteredBasket()
        }
    }

    func pointerExited(_ region: EdgeRootView.Region) {
        switch region {
        case .reveal: pointerNearEdgeChanged(false)
        case .tab: pointerExitedTab()
        case .basket: pointerExitedBasket()
        }
    }

    private func pointerEnteredTab() {
        guard phase == .collapsed, !suppressHoverUntilExit, !app.isPopoverShown, hoverTask == nil else { return }
        withAnimation(.easeOut(duration: 0.18)) { state.isHoveringTab = true }
        let delay = app.preferences.hoverSensitivity.openDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            self.hoverDelayElapsed()
        }
    }

    private func pointerExitedTab() {
        guard phase == .collapsed else { return }
        suppressHoverUntilExit = false
        cancelHover()
        withAnimation(.easeOut(duration: 0.22)) { state.isHoveringTab = false }
    }

    private func pointerEnteredBasket() {
        switch phase {
        case .expanded:
            dismissTask?.cancel()
        case .collapsing:
            if !suppressHoverUntilExit { expand(reason: .hover) }
        case .collapsed, .hidden:
            break
        }
    }

    private func pointerExitedBasket() {
        if phase == .expanded { scheduleDismiss() }
    }

    private func hoverDelayElapsed() {
        guard phase == .collapsed, let geometry, geometry.collapsedFrame.contains(NSEvent.mouseLocation) else {
            withAnimation(.easeOut(duration: 0.22)) { state.isHoveringTab = false }
            return
        }
        expand(reason: .hover)
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func pointerInHoverRegion() -> Bool {
        guard let geometry else { return false }
        return geometry.hoverRegion.contains(NSEvent.mouseLocation)
    }

    private func scheduleDismiss() {
        guard phase == .expanded, holds.isEmpty else { return }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dismissDelay)
            guard !Task.isCancelled, let self else { return }
            if self.phase == .expanded, self.holds.isEmpty, !self.pointerInHoverRegion() {
                self.collapse()
            }
        }
    }

    /// A safety net for a missed exit event (e.g. the basket shrank under a still pointer).
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            var outsideSince: ContinuousClock.Instant?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.phase == .expanded else { return }
                guard self.holds.isEmpty, !self.pointerInHoverRegion() else {
                    outsideSince = nil
                    continue
                }
                let now = ContinuousClock.now
                if let since = outsideSince {
                    if now - since >= .milliseconds(600) {
                        self.collapse()
                        return
                    }
                } else {
                    outsideSince = now
                }
            }
        }
    }

    private func addHold(_ hold: Hold) {
        holds.insert(hold)
        dismissTask?.cancel()
    }

    private func removeHold(_ hold: Hold) {
        guard holds.remove(hold) != nil else { return }
        if holds.isEmpty, phase == .expanded, !pointerInHoverRegion() {
            scheduleDismiss()
        }
    }

    private func cancelPendingWork() {
        cancelHover()
        dismissTask?.cancel()
        watchdogTask?.cancel()
        seenTask?.cancel()
        settleTask?.cancel()
    }

    // MARK: Panel callbacks

    func panelDidBecomeKey() {
        addHold(.keyFocus)
    }

    func panelDidResignKey() {
        removeHold(.keyFocus)
    }

    /// Clicks and drags on the collapsed tab: click opens, vertical drag repositions,
    /// right-click shows a small menu. Clicks on the edge strip beside the tab only reveal it.
    func handleTabEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            cancelHover()
            let onTab = !state.isTabHidden && (geometry?.collapsedFrame.contains(NSEvent.mouseLocation) ?? false)
            tabPress = onTab ? (NSEvent.mouseLocation.y, false) : nil
            return true
        case .leftMouseDragged:
            guard var press = tabPress else { return true }
            let y = NSEvent.mouseLocation.y
            if !press.isRepositioning, abs(y - press.startY) > 4 {
                press.isRepositioning = true
                tabPress = press
                beginReposition(fromScreenY: press.startY)
            }
            if press.isRepositioning { reposition(toScreenY: y) }
            return true
        case .leftMouseUp:
            guard let press = tabPress else { return true }
            tabPress = nil
            if press.isRepositioning {
                endReposition()
            } else {
                suppressHoverUntilExit = false
                expand(reason: .click)
            }
            return true
        case .rightMouseDown:
            showTabMenu(with: event)
            return true
        default:
            return false
        }
    }

    private func showTabMenu(with event: NSEvent) {
        guard let rootView else { return }
        cancelHover()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem("Open Shelf", symbol: "tray") { [weak self] in
            self?.expand(reason: .click)
        })
        menu.addItem(ClosureMenuItem("Clear Shelf", symbol: "xmark.circle",
                                     enabled: !app.collection.items.isEmpty) { [weak self] in
            self?.app.collection.clear()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", symbol: "gearshape") { [weak self] in
            self?.app.openSettings()
        })
        menu.addItem(ClosureMenuItem("Quit Shelfy", symbol: "power") {
            NSApp.terminate(nil)
        })
        NSMenu.popUpContextMenu(menu, with: event, for: rootView)
    }

    // MARK: Repositioning

    private func beginReposition(fromScreenY y: CGFloat) {
        guard let geometry else { return }
        repositionStart = (y, geometry.tabCenterY)
        addHold(.reposition)
    }

    private func reposition(toScreenY y: CGFloat) {
        guard let start = repositionStart, let screen = targetScreen() else { return }
        let centerY = start.centerY + (y - start.mouseY)
        app.preferences.verticalPosition = EdgeGeometry.position(
            forTabCenterY: centerY, visibleFrame: screen.visibleFrame, tabHeight: Self.tabSize.height)
    }

    private func endReposition() {
        repositionStart = nil
        removeHold(.reposition)
        if phase == .collapsed {
            isPointerNearEdge = geometry?.revealedFrame.contains(NSEvent.mouseLocation) ?? false
            applyTabPresence()
        }
    }

    // MARK: Content

    /// The collection or the basket's mode changed: resize the open basket smoothly, or update
    /// whether the collapsed tab should be on screen at all.
    func contentDidChange() {
        basket.collectionDidChange()
        guard phase == .expanded, let geometry = computeGeometry() else {
            if phase == .collapsed { relayout() }
            return
        }
        self.geometry = geometry
        // Grow the panel first so the animation isn't clipped; trim it once things settle.
        setPanelFrame(state.windowFrame.union(geometry.expandedFrame))
        withAnimation(app.accessibility.reduceMotion ? .easeInOut(duration: 0.15)
                                                     : .spring(response: 0.38, dampingFraction: 0.86)) {
            state.basketRect = geometry.basketRect
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, self.phase == .expanded, let geometry = self.geometry else { return }
            self.setPanelFrame(geometry.expandedFrame)
        }
    }

    /// A download arrived: the tab peeks out with a small nudge (or stays quiet when arrival
    /// animation is off), even if it was waiting out of sight.
    func playArrival() {
        switch phase {
        case .expanded:
            scheduleSeen()
        case .collapsed:
            if app.preferences.arrivalAnimation {
                peek(for: .seconds(4), nudge: true)
            } else {
                applyTabPresence()
            }
        case .collapsing, .hidden:
            break
        }
    }

    private func scheduleSeen() {
        seenTask?.cancel()
        seenTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.phase == .expanded else { return }
            self.app.collection.markAllSeen()
        }
    }

    // MARK: Full screen

    func updateFullScreenState() {
        guard phase != .hidden, let screen = targetScreen() else { return }
        let isFull = FullScreenMonitor.isShowingFullScreenApp(on: screen)
        guard isFull != isFullScreenSpace else { return }
        isFullScreenSpace = isFull
        Log.edge.info("Full-screen app on the tab's display: \(isFull, privacy: .public)")
        if isFull, phase == .expanded { collapse(explicit: false) }
        if phase == .collapsed {
            isPointerNearEdge = isFull && (geometry?.revealedFrame.contains(NSEvent.mouseLocation) ?? false)
            applyTabPresence()
        }
    }

    // MARK: Menus

    /// Any menu (context menus, the Open With submenu, SwiftUI menus) keeps the basket open.
    private func observeMenuTracking() {
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.addHold(.menu) }
        })
        menuObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil,
                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeHold(.menu) }
        })
    }
}

// MARK: - BasketHost

extension EdgeController: BasketHost {
    func basketRequestsCollapse() {
        collapse(explicit: true)
    }

    func basketRequestsKeyFocus() {
        focusPanel()
    }

    func basketContentSizeDidChange() {
        contentDidChange()
    }

    func basketDragDidBegin() {
        addHold(.drag)
    }

    func basketDragDidEnd(success: Bool) {
        removeHold(.drag)
        guard success else { return }
        // The file landed somewhere: tuck the basket away once the drop settles.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.collapse(explicit: true)
        }
    }

    func basketQuickLookDidChange(visible: Bool) {
        if visible { addHold(.quickLook) } else { removeHold(.quickLook) }
    }

    func basketBeginReposition() {
        beginReposition(fromScreenY: NSEvent.mouseLocation.y)
    }

    func basketReposition(toScreenY y: CGFloat) {
        reposition(toScreenY: y)
    }

    func basketEndReposition() {
        endReposition()
    }
}
