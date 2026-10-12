import CoreServices
import Foundation

/// Watches the top level of a folder with FSEvents and reports files once they have
/// finished downloading.
///
/// A new entry becomes a *candidate*. It's reported as ready only after its size and
/// modification date have stopped changing, it no longer carries the Finder "busy" date,
/// and no sibling partial file (`name.part`, `name.crdownload`, …) is present. Temporary
/// artifacts are never reported; a rename from a temporary name to a final name is what
/// completes most browser downloads.
///
/// All state is confined to a private serial queue. The handler is called on that queue
/// and must not block on the main thread.
nonisolated final class DownloadObserver: @unchecked Sendable {
    struct Options: Sendable {
        var latency: TimeInterval = 0.15
        var settleInterval: TimeInterval = 0.9
        var directorySettleInterval: TimeInterval = 1.5
        var pollInterval: TimeInterval = 0.3
        /// Empty files are held back a little longer; Firefox creates an empty placeholder
        /// before the real data arrives.
        var emptyFileGrace: TimeInterval = 4
        var candidateLifetime: TimeInterval = 6 * 3600
        /// When set, entries added to the folder after this date (and within `catchUpWindow`)
        /// are reported at start. Used to pick up downloads that finished while Shelfy was quit.
        var catchUpSince: Date?
        var catchUpWindow: TimeInterval = 12 * 3600
    }

    enum Event: Sendable {
        /// `isCatchUp` marks files found at start that arrived while Shelfy wasn't running.
        case fileReady(URL, isCatchUp: Bool)
        /// Something left the folder; basket references may need revalidating.
        case entriesRemoved
        case folderUnavailable
    }

    let folderURL: URL
    private let folderPath: String
    private let options: Options
    private let handler: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "com.benbreslow.Shelfy.DownloadObserver", qos: .utility)

    // Queue-confined state.
    private var stream: FSEventStreamRef?
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    /// Current top-level entries: name → inode.
    private var entries: [String: UInt64] = [:]
    /// The last name each inode had in this folder. Kept after removal so a rename is
    /// recognized regardless of the order its two events arrive in.
    private var lastNameForInode: [UInt64: String] = [:]
    private var candidates: [String: Candidate] = [:]

    private struct Candidate {
        var inode: UInt64
        var firstSeen: Date
        var lastChange: Date
        var signature: Signature
        var isCatchUp = false
    }

    private struct Signature: Equatable {
        var size: Int64
        var modified: TimeInterval
        var childCount: Int
    }

    init(folder: URL, options: Options = Options(), handler: @escaping @Sendable (Event) -> Void) {
        folderURL = folder
        folderPath = Self.canonicalPath(of: folder)
        self.options = options
        self.handler = handler
    }

    func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            guard takeSnapshot() else {
                Log.files.error("Cannot read watched folder \(Log.redacted(self.folderPath), privacy: .public)")
                handler(.folderUnavailable)
                return
            }
            startStream()
            catchUp()
            Log.files.info("Watching \(Log.redacted(self.folderPath), privacy: .public) (\(self.entries.count) existing entries)")
        }
    }

    /// Stops watching. Safe to call from the main thread; returns once no more events can fire.
    func stop() {
        queue.sync { [self] in
            isRunning = false
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            stream = nil
            timer?.cancel()
            timer = nil
            candidates.removeAll()
        }
    }

    // MARK: Snapshot and catch-up

    private func takeSnapshot() -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else { return false }
        entries.removeAll()
        for name in names {
            guard let status = FileStatus(path: path(name)) else { continue }
            entries[name] = status.inode
            lastNameForInode[status.inode] = name
        }
        return true
    }

    private func catchUp() {
        guard let since = options.catchUpSince else { return }
        let now = Date()
        let earliest = max(since, now.addingTimeInterval(-options.catchUpWindow))
        for name in entries.keys where !DownloadNaming.isIgnored(name) {
            let url = URL(fileURLWithPath: path(name))
            let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            guard let added = values?.addedToDirectoryDate ?? values?.creationDate, added > earliest,
                  let status = FileStatus(path: url.path), !status.isSymbolicLink else { continue }
            Log.files.info("Catching up on \(Log.redacted(name), privacy: .public), added while Shelfy wasn't running")
            addCandidate(name, status, now: now)
            candidates[name]?.isCatchUp = true
        }
        scheduleTimerIfNeeded()
    }

    // MARK: FSEvents

    private func startStream() {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                             | kFSEventStreamCreateFlagNoDefer
                                             | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, downloadObserverCallback, &context,
                                               [folderPath] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               options.latency, flags) else {
            handler(.folderUnavailable)
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    fileprivate func handle(_ events: [(path: String, flags: Int)]) {
        guard isRunning else { return }
        var names: [String] = []
        var seen = Set<String>()
        var needsRescan = false
        let rescanFlags = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
        for event in events {
            if event.flags & rescanFlags != 0 { needsRescan = true; continue }
            if event.flags & kFSEventStreamEventFlagRootChanged != 0 { handleRootChanged(); continue }
            let path = event.path as NSString
            guard path.deletingLastPathComponent.compare(folderPath, options: .caseInsensitive) == .orderedSame
            else { continue } // only top-level entries; contents of subfolders and bundles don't count
            let name = path.lastPathComponent
            if seen.insert(name).inserted { names.append(name) }
        }
        var removed = false
        if needsRescan { removed = rescan() }
        for name in names where process(name) == .removed { removed = true }
        if removed { handler(.entriesRemoved) }
        scheduleTimerIfNeeded()
    }

    private func handleRootChanged() {
        guard FileStatus(path: folderPath)?.isDirectory == true else {
            Log.files.error("Watched folder moved or deleted")
            handler(.folderUnavailable)
            return
        }
        _ = rescan()
    }

    private func rescan() -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else {
            handler(.folderUnavailable)
            return false
        }
        let current = Set(names)
        var removed = false
        for name in entries.keys where !current.contains(name) {
            entries.removeValue(forKey: name)
            candidates.removeValue(forKey: name)
            removed = true
        }
        for name in names { process(name) }
        return removed
    }

    private enum Change { case none, candidate, removed }

    /// Updates bookkeeping for one top-level name and decides whether it's a new arrival.
    @discardableResult
    private func process(_ name: String) -> Change {
        guard let status = FileStatus(path: path(name)) else {
            candidates.removeValue(forKey: name)
            return entries.removeValue(forKey: name) == nil ? .none : .removed
        }
        let inode = status.inode
        let previousName = lastNameForInode[inode]
        let knownUnderThisName = entries[name] == inode
        if let previousName, previousName != name, entries[previousName] == inode {
            entries.removeValue(forKey: previousName)
            candidates.removeValue(forKey: previousName)
        }
        entries[name] = inode
        lastNameForInode[inode] = name

        guard !DownloadNaming.isIgnored(name), !status.isSymbolicLink else {
            candidates.removeValue(forKey: name)
            return .none
        }
        if candidates[name]?.inode == inode { return .none } // already waiting for it to settle

        let isArrival: Bool
        if knownUnderThisName {
            isArrival = false // a write to, or metadata change of, a file that was already here
        } else if let previousName {
            isArrival = DownloadNaming.isIgnored(previousName) // "x.crdownload" → "x" finishes a download
        } else {
            isArrival = true // created here, or moved in from elsewhere
        }
        guard isArrival else {
            candidates.removeValue(forKey: name)
            return .none
        }
        addCandidate(name, status, now: Date())
        Log.files.debug("Candidate \(Log.redacted(name), privacy: .public)")
        return .candidate
    }

    // MARK: Settling

    private func addCandidate(_ name: String, _ status: FileStatus, now: Date) {
        candidates[name] = Candidate(inode: status.inode, firstSeen: now, lastChange: now,
                                     signature: signature(of: status, name: name))
    }

    private func scheduleTimerIfNeeded() {
        guard timer == nil, !candidates.isEmpty, isRunning else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + options.pollInterval, repeating: options.pollInterval,
                       leeway: .milliseconds(40))
        timer.setEventHandler { [weak self] in self?.evaluateCandidates() }
        timer.resume()
        self.timer = timer
    }

    private func evaluateCandidates() {
        let now = Date()
        for (name, candidate) in candidates {
            // Gone, or replaced by a different file (which arrives through its own event).
            guard let status = FileStatus(path: path(name)), status.inode == candidate.inode else {
                candidates.removeValue(forKey: name)
                continue
            }
            let current = signature(of: status, name: name)
            if current != candidate.signature {
                candidates[name]?.signature = current
                candidates[name]?.lastChange = now
                continue
            }
            if now.timeIntervalSince(candidate.firstSeen) > options.candidateLifetime {
                candidates.removeValue(forKey: name) // e.g. a download abandoned mid-way
                continue
            }
            let settle = status.isDirectory ? options.directorySettleInterval : options.settleInterval
            guard now.timeIntervalSince(candidate.lastChange) >= settle else { continue }
            guard !hasSiblingMarker(name), !DownloadNaming.hasBusyCreationDate(status) else { continue }
            if !status.isDirectory, status.size == 0,
               now.timeIntervalSince(candidate.firstSeen) < options.emptyFileGrace { continue }

            candidates.removeValue(forKey: name)
            Log.files.info("Download ready: \(Log.redacted(name), privacy: .public)")
            handler(.fileReady(URL(fileURLWithPath: path(name), isDirectory: status.isDirectory),
                               isCatchUp: candidate.isCatchUp))
        }
        if candidates.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }

    private func signature(of status: FileStatus, name: String) -> Signature {
        var childCount = 0
        if status.isDirectory {
            childCount = (try? FileManager.default.contentsOfDirectory(atPath: path(name)).count) ?? 0
        }
        return Signature(size: status.size, modified: status.modified, childCount: childCount)
    }

    private func hasSiblingMarker(_ name: String) -> Bool {
        DownloadNaming.siblingMarkerNames(for: name).contains { FileStatus(path: path($0)) != nil }
    }

    private func path(_ name: String) -> String {
        folderPath + "/" + name
    }

    /// FSEvents reports real paths (`/private/var/...`), so compare against `realpath`.
    static func canonicalPath(of url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

private nonisolated func downloadObserverCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ paths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let observer = Unmanaged<DownloadObserver>.fromOpaque(info).takeUnretainedValue()
    let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    var events: [(path: String, flags: Int)] = []
    events.reserveCapacity(count)
    for index in 0..<count {
        events.append((String(cString: cPaths[index]), Int(flags[index])))
    }
    observer.handle(events)
}
