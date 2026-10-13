import Foundation

/// Finds the current location of a basket item's file.
nonisolated enum FileLocator {
    enum Outcome: Equatable, Sendable {
        /// The original file, possibly renamed or moved. `bookmark` is non-nil when it was refreshed.
        case found(URL, bookmark: Data?)
        /// The file may still exist, but Shelfy isn't allowed to look (e.g. folder access revoked).
        case inaccessible
        /// Deleted, moved to the Trash, or replaced by a different file with the same name.
        case gone
    }

    enum Probe: Equatable { case same, different, missing, inaccessible }

    static func locate(_ item: BasketItem) -> Outcome {
        var sawPermissionError = false
        if let data = item.bookmark {
            var isStale = false
            let options: URL.BookmarkResolutionOptions = item.bookmarkIsSecurityScoped
                ? [.withSecurityScope, .withoutUI, .withoutMounting]
                : [.withoutUI, .withoutMounting]
            if let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) {
                switch probe(url, for: item) {
                case .same:
                    var refreshed: Data?
                    if isStale {
                        let scope: URL.BookmarkCreationOptions = item.bookmarkIsSecurityScoped
                            ? [.withSecurityScope] : []
                        refreshed = try? url.bookmarkData(options: scope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    }
                    return .found(url, bookmark: refreshed)
                case .inaccessible:
                    sawPermissionError = true
                case .different, .missing:
                    break
                }
            }
        }
        switch probe(item.url, for: item) {
        case .same: return .found(item.url, bookmark: nil)
        case .inaccessible: return .inaccessible
        case .different, .missing: return sawPermissionError ? .inaccessible : .gone
        }
    }

    /// Bookmarks fall back to the original path when the file is gone, so a new download that
    /// reused the name must not be mistaken for the original: compare inodes.
    static func probe(_ url: URL, for item: BasketItem) -> Probe {
        if isInTrash(url) { return .missing }
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            return (errno == EPERM || errno == EACCES) ? .inaccessible : .missing
        }
        if let fileNumber = item.fileNumber, UInt64(info.st_ino) != fileNumber { return .different }
        return .same
    }

    static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}
