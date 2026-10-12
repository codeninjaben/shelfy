import AppKit

/// Recognizes a pointer that is clearly heading for the edge tab, so the tab can stick out
/// before the pointer arrives. It never opens the basket; only resting on the tab does that.
///
/// Three things have to agree:
/// - **Aim (the triangle).** Following the pointer's recent velocity to the edge lands on the
///   tab, give or take a tolerance that widens with distance, so aiming from farther out
///   needn't be precise.
/// - **Commitment.** The pointer isn't braking to stop short of the edge. A quick move to a
///   sidebar item near the edge looks like a reach for the tab until it decelerates, so the
///   model estimates where the pointer will stop from its recent deceleration.
/// - **Deliberateness.** The pointer is moving with some speed, inside a zone near the tab.
nonisolated struct ApproachModel {
    struct Target: Equatable {
        var edge: ScreenEdge
        var edgeX: CGFloat
        var tabMinY: CGFloat
        var tabMaxY: CGFloat
        var tabCenterY: CGFloat { (tabMinY + tabMaxY) / 2 }
    }

    struct Tuning: Equatable {
        /// How far from the edge an approach can be recognized.
        var reach: CGFloat
        /// How far above or below the tab the pointer may be.
        var verticalReach: CGFloat
        /// Minimum pointer speed, in points per second, that reads as deliberate.
        var minSpeed: CGFloat
        /// Tolerance around the tab where the heading must meet the edge, right at the edge…
        var slack: CGFloat
        /// …widening by this much per point of distance from the edge.
        var slackPerPoint: CGFloat
    }

    /// Velocity is measured over this much recent movement.
    static let velocityWindow: TimeInterval = 0.12
    static let minimumSpan: TimeInterval = 0.04
    /// A pointer predicted to stop before covering this share of the remaining distance is
    /// aiming at something short of the edge.
    static let stoppingShare: CGFloat = 0.7
    /// Once approaching, the zone grows a little so the tab doesn't flicker at its border.
    static let exitMargin: CGFloat = 40

    var target: Target?
    var tuning: Tuning
    private(set) var isApproaching = false
    private(set) var lastSampleTime: TimeInterval = 0
    private var samples: [(point: CGPoint, time: TimeInterval)] = []

    init(tuning: Tuning) {
        self.tuning = tuning
    }

    mutating func reset() {
        samples.removeAll()
        isApproaching = false
    }

    /// Feeds one pointer position (screen coordinates). Returns true when `isApproaching` changed.
    @discardableResult
    mutating func update(location point: CGPoint, time: TimeInterval) -> Bool {
        let wasApproaching = isApproaching
        guard let target else {
            reset()
            return wasApproaching
        }
        lastSampleTime = time
        let distance = target.edge == .right ? target.edgeX - point.x : point.x - target.edgeX
        let margin = isApproaching ? Self.exitMargin : 0
        let inZone = distance >= -1 && distance <= tuning.reach + margin
            && abs(point.y - target.tabCenterY) <= tuning.verticalReach + margin
        guard inZone else {
            samples.removeAll()
            isApproaching = false
            return wasApproaching
        }

        samples.append((point, time))
        samples.removeAll { time - $0.time > Self.velocityWindow }
        guard let first = samples.first, time - first.time >= Self.minimumSpan else { return false }
        let velocity = Self.velocity(from: first, to: (point, time))
        let towardEdge = target.edge == .right ? velocity.dx : -velocity.dx
        let speed = hypot(velocity.dx, velocity.dy)

        if !isApproaching {
            guard speed >= tuning.minSpeed, towardEdge >= tuning.minSpeed * 0.4 else { return false }
            let remaining = max(distance, 0)
            guard isCommitted(remaining: remaining, target: target, now: time) else { return false }
            let arrivalY = point.y + velocity.dy * (remaining / towardEdge)
            let slack = tuning.slack + tuning.slackPerPoint * remaining
            if arrivalY >= target.tabMinY - slack, arrivalY <= target.tabMaxY + slack {
                isApproaching = true
            }
        } else if towardEdge <= -tuning.minSpeed {
            isApproaching = false // clearly heading back into the screen
        }
        return wasApproaching != isApproaching
    }

    /// Compares the older and newer halves of the window: a pointer braking hard enough to
    /// stop well short of the edge is reaching for something else.
    private func isCommitted(remaining: CGFloat, target: Target, now: TimeInterval) -> Bool {
        guard remaining > 12, let first = samples.first, let last = samples.last else { return true }
        let middleTime = (first.time + now) / 2
        guard let middle = samples.min(by: { abs($0.time - middleTime) < abs($1.time - middleTime) }),
              middle.time - first.time >= 0.012, last.time - middle.time >= 0.012 else { return true }
        let sign: CGFloat = target.edge == .right ? 1 : -1
        let older = Self.velocity(from: first, to: middle).dx * sign
        let newer = Self.velocity(from: middle, to: last).dx * sign
        guard newer > 0 else { return false }
        let braking = (older - newer) / CGFloat((last.time - first.time) / 2)
        guard braking > 0 else { return true } // steady or speeding up
        let stoppingDistance = newer * newer / (2 * braking)
        return stoppingDistance >= remaining * Self.stoppingShare
    }

    private static func velocity(from start: (point: CGPoint, time: TimeInterval),
                                 to end: (point: CGPoint, time: TimeInterval)) -> CGVector {
        let elapsed = CGFloat(max(end.time - start.time, 0.001))
        return CGVector(dx: (end.point.x - start.point.x) / elapsed, dy: (end.point.y - start.point.y) / elapsed)
    }
}

extension HoverSensitivity {
    /// Higher sensitivity recognizes approaches from farther away and with less precise aim.
    nonisolated var approachTuning: ApproachModel.Tuning {
        switch self {
        case .low: ApproachModel.Tuning(reach: 160, verticalReach: 220, minSpeed: 200, slack: 24, slackPerPoint: 0.18)
        case .medium: ApproachModel.Tuning(reach: 220, verticalReach: 300, minSpeed: 150, slack: 36, slackPerPoint: 0.25)
        case .high: ApproachModel.Tuning(reach: 300, verticalReach: 380, minSpeed: 110, slack: 48, slackPerPoint: 0.32)
        }
    }
}

/// Feeds pointer movement to an `ApproachModel` while the tab is tucked away.
///
/// Uses AppKit event monitors for mouse movement only: no permissions are needed, nothing
/// is recorded beyond the last tenth of a second of movement, and the monitors are removed
/// whenever the basket is open or the tab is off the edge. Positions outside the approach
/// zone are discarded on arrival.
///
/// A global monitor can silently stop delivering events across sleep and screen lock, so
/// the monitors are reinstalled when the system wakes or the screen unlocks, and a cheap
/// health check reinstalls them if the system reports pointer movement that never arrived.
@MainActor
final class ApproachTracker {
    var onChange: ((Bool) -> Void)?
    private var model = ApproachModel(tuning: HoverSensitivity.medium.approachTuning)
    private var monitors: [Any] = []
    /// Whether the owner wants tracking on; survives reinstalling the monitors.
    private var wantsToRun = false
    /// System uptime of the last pointer event either monitor delivered.
    private var lastEventTime: TimeInterval = 0
    private var installedAt: TimeInterval = 0
    private var healthCheck: Task<Void, Never>?
    private var systemObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    #if DEBUG
    private var hasReportedFirstEvent = false
    private var hasReportedHealthCheck = false
    #endif

    /// How often the health check runs while tracking.
    static let healthCheckInterval: Duration = .seconds(30)

    init() {
        observeWakeAndUnlock()
    }

    var isApproaching: Bool { model.isApproaching }
    var isRunning: Bool { !monitors.isEmpty }
    /// System uptime of the last movement seen in the approach zone.
    var lastActivity: TimeInterval { model.lastSampleTime }

    func configure(target: ApproachModel.Target?, tuning: ApproachModel.Tuning) {
        if model.target != target || model.tuning != tuning {
            model.target = target
            model.tuning = tuning
            model.reset()
        }
    }

    /// Forgets the current approach, e.g. after the controller decided it stalled.
    func reset() {
        model.reset()
    }

    func setRunning(_ running: Bool) {
        wantsToRun = running
        if running { install() } else { uninstall() }
    }

    /// Reinstalls the monitors if tracking is wanted. Global monitors can stop delivering
    /// events after sleep or a screen lock without any error.
    func rearm(reason: String) {
        guard wantsToRun else { return }
        uninstall(log: false)
        install(log: false)
        Log.edge.info("Approach tracking re-armed (\(reason, privacy: .public))")
    }

    // MARK: Monitors

    private func install(log: Bool = true) {
        guard monitors.isEmpty else { return }
        // Moves only, not drags: someone dragging a file past the edge isn't reaching for Shelfy.
        let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let time = event.timestamp
            MainActor.assumeIsolated { self?.pointerMoved(at: time) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let time = event.timestamp
            MainActor.assumeIsolated { self?.pointerMoved(at: time) }
            return event
        }
        monitors = [global, local].compactMap { $0 }
        installedAt = ProcessInfo.processInfo.systemUptime
        startHealthCheck()
        if global == nil {
            Log.edge.error("Approach tracking couldn't install its global pointer monitor")
        } else if log {
            Log.edge.info("Approach tracking on")
        }
    }

    private func uninstall(log: Bool = true) {
        healthCheck?.cancel()
        healthCheck = nil
        guard !monitors.isEmpty else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        model.reset()
        if log { Log.edge.info("Approach tracking off") }
    }

    private func pointerMoved(at time: TimeInterval) {
        lastEventTime = time
        #if DEBUG
        if !hasReportedFirstEvent {
            hasReportedFirstEvent = true
            Log.edge.info("Approach tracker is receiving pointer movement")
        }
        #endif
        if model.update(location: NSEvent.mouseLocation, time: time) {
            onChange?(model.isApproaching)
        }
    }

    // MARK: Staying alive

    private func observeWakeAndUnlock() {
        let workspace = NSWorkspace.shared.notificationCenter
        let wakeNotifications = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                                 NSWorkspace.sessionDidBecomeActiveNotification]
        for name in wakeNotifications {
            let reason = name.rawValue
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rearm(reason: reason) }
            }
            systemObservers.append((workspace, token))
        }
        let distributed = DistributedNotificationCenter.default()
        let token = distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rearm(reason: "screen unlocked") }
        }
        systemObservers.append((distributed, token))
    }

    /// Every so often, compare what the monitor heard with what the system saw. Reads only
    /// how long ago the pointer last moved, never where it is.
    private func startHealthCheck() {
        healthCheck?.cancel()
        healthCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.healthCheckInterval)
                guard !Task.isCancelled, let self, self.isRunning else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let systemMouseIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
                #if DEBUG
                if !self.hasReportedHealthCheck {
                    self.hasReportedHealthCheck = true
                    Log.edge.info("Approach health check: pointer last moved \(systemMouseIdle, format: .fixed(precision: 1), privacy: .public) s ago, last event \(now - max(self.lastEventTime, self.installedAt), format: .fixed(precision: 1), privacy: .public) s ago")
                }
                #endif
                if Self.monitorLooksStalled(now: now, lastEvent: max(self.lastEventTime, self.installedAt),
                                            systemMouseIdle: systemMouseIdle) {
                    self.rearm(reason: "pointer moved but no events arrived")
                }
            }
        }
    }

    /// True when the system reports recent pointer movement but the monitor has been silent
    /// for longer than a health-check interval.
    nonisolated static func monitorLooksStalled(now: TimeInterval, lastEvent: TimeInterval,
                                                systemMouseIdle: TimeInterval) -> Bool {
        systemMouseIdle < 10 && now - lastEvent > 30
    }
}
