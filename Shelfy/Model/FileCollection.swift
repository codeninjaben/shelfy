import Foundation
import Observation

/// The single source of truth for what's in the basket. Both the edge basket and the
/// menu-bar popover render this collection, so they always agree.
@MainActor @Observable
final class FileCollection {
    static let capacity = 60
    static let undoWindow: Duration = .seconds(6)

    /// Newest first.
    private(set) var items: [BasketItem] = []
    /// Items that arrived since the basket was last looked at.
    private(set) var unseen: Set<UUID> = []
    /// Items removed by "Clear", kept briefly so the clear can be undone.
    private(set) var clearedItems: [BasketItem]?
    /// Files the last "Move to Trash" sent to the Trash, kept briefly so they can be put back.
    private(set) var trashedItems: [TrashedItem]?
    /// A short-lived problem to show in place of the summary.
    private(set) var notice: Notice?

    /// A file in the Trash and where it sat on the shelf.
    nonisolated struct TrashedItem: Sendable {
        /// The item as it was, `url` being where the file lived before the Trash.
        let item: BasketItem
        let trashURL: URL
        let index: Int
    }

    nonisolated enum Notice: Equatable, Sendable {
        case trashFailed, putBackFailed
    }

    @ObservationIgnored var onArrival: ((BasketItem) -> Void)?
    @ObservationIgnored var onItemsChanged: (() -> Void)?
    /// Moves a file to the Trash and returns where it ended up. Tests use a scratch folder.
    @ObservationIgnored var trashFile: @Sendable (URL) throws -> URL = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return (resulting as URL?) ?? url
    }
    /// Moves a file from the Trash back to its original location.
    @ObservationIgnored var putBackFile: @Sendable (_ trashURL: URL, _ original: URL) throws -> Void = { trashURL, original in
        try FileManager.default.moveItem(at: trashURL, to: original)
    }
    @ObservationIgnored private let store: BasketStore
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?
    @ObservationIgnored private var noticeExpiry: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(store: BasketStore) {
        self.store = store
    }

    var hasUnseen: Bool { !unseen.isEmpty }
    var canUndoClear: Bool { clearedItems != nil }
    var canPutBack: Bool { trashedItems != nil }
    /// Clear and Move to Trash share one undo, for whichever happened last.
    var canUndo: Bool { canUndoClear || canPutBack }

    func item(withID id: UUID) -> BasketItem? {
        items.first { $0.id == id }
    }

    // MARK: Loading

    /// Restores saved references. Checking them touches the watched folder, which can wait on
    /// the system's privacy prompt, so that part runs in the background.
    func load(revalidatingInBackground: Bool = true) {
        items = store.load()
        Log.app.info("Restored \(self.items.count) basket item(s)")
        if revalidatingInBackground { revalidateInBackground() } else { revalidate() }
    }

    // MARK: Mutations

    /// Adds a newly completed download. A file that's already in the basket moves to the front
    /// instead of appearing twice.
    @discardableResult
    func add(fileAt url: URL) -> BasketItem? {
        guard let fresh = BasketItem(fileAt: url) else {
            Log.files.notice("Skipped \(Log.redacted(url.lastPathComponent), privacy: .public): file disappeared before it could be added")
            return nil
        }
        var item = fresh
        if let index = items.firstIndex(where: { $0.refersToSameFile(as: fresh) }) {
            item = items.remove(at: index)
            _ = item.refresh(at: fresh.url)
            item.addedAt = .now
        }
        items.insert(item, at: 0)
        unseen.insert(item.id)
        trimToCapacity()
        beginAccess(item)
        itemsDidChange()
        onArrival?(item)
        return item
    }

    func remove(_ ids: Set<UUID>) {
        guard items.contains(where: { ids.contains($0.id) }) else { return }
        items.removeAll { ids.contains($0.id) }
        unseen.subtract(ids)
        ids.forEach(endAccess)
        itemsDidChange()
    }

    /// Removes every reference. The files themselves are untouched.
    func clear() {
        guard !items.isEmpty else { return }
        settlePendingUndo()
        clearedItems = items
        items = []
        unseen = []
        itemsDidChange()
        scheduleUndoExpiry()
    }

    func undoClear() {
        guard let restored = clearedItems else { return }
        undoExpiry?.cancel()
        clearedItems = nil
        let present = items
        items = present + restored.filter { old in !present.contains { $0.refersToSameFile(as: old) } }
        revalidate(notify: false)
        itemsDidChange()
    }

    /// Undoes whichever of Clear and Move to Trash happened last.
    func undo() {
        if canPutBack { putBack() } else { undoClear() }
    }

    // MARK: Trash

    /// Moves the files themselves to the Trash and takes them off the shelf. The moves run off the
    /// main thread; a file that can't be moved comes back to the shelf with a notice.
    @discardableResult
    func moveToTrash(_ ids: Set<UUID>) -> Task<Void, Never>? {
        let targets = items.enumerated().compactMap { index, item in
            ids.contains(item.id) ? (index: index, item: item) : nil
        }
        guard !targets.isEmpty else { return nil }
        settlePendingUndo()
        items.removeAll { ids.contains($0.id) }
        unseen.subtract(ids)
        itemsDidChange()
        let trashFile = trashFile
        return Task.detached(priority: .userInitiated) { [weak self] in
            var trashed: [TrashedItem] = []
            var failed: [(index: Int, item: BasketItem)] = []
            for (index, item) in targets {
                switch FileLocator.locate(item) {
                case .gone:
                    continue // already deleted or trashed elsewhere: nothing left to move
                case .inaccessible:
                    failed.append((index, item))
                case .found(let url, _):
                    do {
                        var original = item
                        original.url = url
                        trashed.append(TrashedItem(item: original, trashURL: try trashFile(url), index: index))
                    } catch {
                        Log.files.error("Could not move \(Log.redacted(item.name), privacy: .public) to the Trash: \(error.localizedDescription, privacy: .public)")
                        failed.append((index, item))
                    }
                }
            }
            await self?.finishTrash(targets.map(\.item.id), trashed: trashed, failed: failed)
        }
    }

    /// Moves the files from the last "Move to Trash" back where they were and returns them to
    /// their old places on the shelf.
    @discardableResult
    func putBack() -> Task<Void, Never>? {
        guard let batch = trashedItems else { return nil }
        undoExpiry?.cancel()
        trashedItems = nil
        let putBackFile = putBackFile
        return Task.detached(priority: .userInitiated) { [weak self] in
            var restored: [TrashedItem] = []
            var failures = 0
            for entry in batch {
                do {
                    // Never replace a file that has taken the old name in the meantime.
                    guard FileStatus(path: entry.item.url.path) == nil else { throw CocoaError(.fileWriteFileExists) }
                    try putBackFile(entry.trashURL, entry.item.url)
                    restored.append(entry)
                } catch {
                    Log.files.error("Could not put back \(Log.redacted(entry.item.name), privacy: .public): \(error.localizedDescription, privacy: .public)")
                    failures += 1
                }
            }
            await self?.finishPutBack(restored, failures: failures)
        }
    }

    private func finishTrash(_ ids: [UUID], trashed: [TrashedItem], failed: [(index: Int, item: BasketItem)]) {
        let failedIDs = Set(failed.map(\.item.id))
        ids.filter { !failedIDs.contains($0) }.forEach(endAccess)
        if !trashed.isEmpty {
            Log.files.info("Moved \(trashed.count) file(s) to the Trash")
            trashedItems = trashed
            scheduleUndoExpiry()
        }
        guard !failed.isEmpty else {
            onItemsChanged?()
            return
        }
        for entry in failed.sorted(by: { $0.index < $1.index })
        where !items.contains(where: { $0.refersToSameFile(as: entry.item) }) {
            items.insert(entry.item, at: min(entry.index, items.count))
        }
        show(.trashFailed)
        itemsDidChange()
    }

    private func finishPutBack(_ restored: [TrashedItem], failures: Int) {
        for entry in restored.sorted(by: { $0.index < $1.index }) {
            var item = entry.item
            _ = item.refresh(at: item.url)
            item.makeBookmark()
            for duplicate in items where duplicate.refersToSameFile(as: item) { endAccess(duplicate.id) }
            items.removeAll { $0.refersToSameFile(as: item) }
            items.insert(item, at: min(entry.index, items.count))
            beginAccess(item)
        }
        if failures > 0 { show(.putBackFailed) }
        itemsDidChange()
    }

    private func show(_ notice: Notice) {
        self.notice = notice
        noticeExpiry?.cancel()
        noticeExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            self.notice = nil
            self.onItemsChanged?() // the footer may shrink back
        }
    }

    func markAllSeen() {
        guard !unseen.isEmpty else { return }
        unseen.removeAll()
        onItemsChanged?()
    }

    /// Follows renamed and moved files, drops items whose files were deleted, trashed or
    /// replaced, and marks items Shelfy can no longer read.
    func revalidate(notify: Bool = true) {
        apply(items.map { Self.check($0) }, notify: notify)
    }

    /// The same check off the main thread; results are applied to whatever is still in the basket.
    func revalidateInBackground() {
        let snapshot = items
        guard !snapshot.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            let results = snapshot.map { Self.check($0) }
            await self?.apply(results, notify: true)
        }
    }

    private enum Check: Sendable {
        case keep(BasketItem)
        case drop(UUID)
    }

    private nonisolated static func check(_ item: BasketItem) -> Check {
        var item = item
        switch FileLocator.locate(item) {
        case .gone:
            return .drop(item.id)
        case .inaccessible:
            // Permission trouble isn't deletion: keep the reference, show it as unavailable.
            item.isReadable = false
            return .keep(item)
        case .found(let url, let bookmark):
            if let bookmark { item.bookmark = bookmark }
            _ = item.refresh(at: url)
            return .keep(item)
        }
    }

    private func apply(_ results: [Check], notify: Bool) {
        var updated: [UUID: BasketItem] = [:]
        var dropped = Set<UUID>()
        for result in results {
            switch result {
            case .keep(let item): updated[item.id] = item
            case .drop(let id): dropped.insert(id)
            }
        }
        var changed = false
        var survivors: [BasketItem] = []
        survivors.reserveCapacity(items.count)
        for item in items {
            if dropped.contains(item.id) {
                Log.files.info("Removed reference to \(Log.redacted(item.name), privacy: .public): file is gone")
                endAccess(item.id)
                unseen.remove(item.id)
                changed = true
            } else if let refreshed = updated[item.id], refreshed != item {
                survivors.append(refreshed)
                beginAccess(refreshed)
                changed = true
            } else {
                survivors.append(item) // unchanged, or added after the check started
            }
        }
        guard changed else { return }
        items = survivors
        if notify { itemsDidChange() } else { scheduleSave() }
    }

    func saveNow() {
        pendingSave?.cancel()
        store.save(items)
    }

    // MARK: Private

    /// A new undoable action replaces the previous one: let go of what that one was holding.
    private func settlePendingUndo() {
        undoExpiry?.cancel()
        clearedItems?.forEach { endAccess($0.id) }
        clearedItems = nil
        trashedItems = nil
    }

    private func scheduleUndoExpiry() {
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.expireUndo()
        }
    }

    private func expireUndo() {
        clearedItems?.forEach { endAccess($0.id) }
        clearedItems = nil
        trashedItems = nil
        onItemsChanged?()
    }

    private func trimToCapacity() {
        guard items.count > Self.capacity else { return }
        let overflow = items[Self.capacity...]
        overflow.forEach { endAccess($0.id); unseen.remove($0.id) }
        items.removeLast(items.count - Self.capacity)
    }

    private func itemsDidChange() {
        scheduleSave()
        onItemsChanged?()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.store.save(self.items)
        }
    }

    /// Security-scoped bookmarks only grant access while "accessing"; keep that open for as
    /// long as the item is in the basket so thumbnails, Quick Look and drags keep working
    /// after the file moves out of the watched folder.
    private func beginAccess(_ item: BasketItem) {
        guard item.bookmarkIsSecurityScoped, scopedURLs[item.id] != item.url else { return }
        endAccess(item.id)
        guard let data = item.bookmark else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return }
        if url.startAccessingSecurityScopedResource() {
            scopedURLs[item.id] = url
        }
    }

    private func endAccess(_ id: UUID) {
        scopedURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    }
}
