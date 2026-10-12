import Foundation
import UniformTypeIdentifiers

/// A reference to a file that arrived in the watched folder.
///
/// Shelfy never moves or copies the file itself. It remembers where the file lives through a
/// bookmark plus the file's identity (inode and volume), so it can follow renames and moves
/// and notice when a different file has taken over the same name.
nonisolated struct BasketItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var url: URL
    var bookmark: Data?
    var bookmarkIsSecurityScoped: Bool
    var fileNumber: UInt64?
    var volumeID: String?
    var name: String
    var addedAt: Date
    var byteCount: Int64?
    var contentTypeIdentifier: String?
    var isDirectory: Bool
    var modifiedAt: Date?
    var isReadable: Bool

    var contentType: UTType? { contentTypeIdentifier.flatMap(UTType.init) }
    var kind: ItemKind { ItemKind(contentType: contentType, isDirectory: isDirectory) }

    /// "PDF document · 2.4 MB"
    var detailText: String {
        var parts: [String] = []
        if let description = contentType?.localizedDescription, !description.isEmpty {
            parts.append(description.prefix(1).uppercased() + description.dropFirst())
        } else if isDirectory {
            parts.append("Folder")
        }
        if let byteCount, !isDirectory {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        }
        if !isReadable { parts.append("No Access") }
        return parts.joined(separator: " · ")
    }

    func refersToSameFile(as other: BasketItem) -> Bool {
        guard let fileNumber, let otherNumber = other.fileNumber else {
            return url.standardizedFileURL == other.url.standardizedFileURL
        }
        return fileNumber == otherNumber && volumeID == other.volumeID
    }
}

nonisolated extension BasketItem {
    static let resourceKeys: Set<URLResourceKey> = [
        .nameKey, .fileSizeKey, .contentTypeKey, .isDirectoryKey, .isPackageKey,
        .contentModificationDateKey, .volumeUUIDStringKey,
    ]

    /// Builds an item from a file on disk. Returns nil when the file is gone.
    nonisolated init?(fileAt url: URL, addedAt: Date = .now) {
        let url = url.standardizedFileURL
        guard let status = FileStatus(path: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: Self.resourceKeys)
        let isPackage = values?.isPackage ?? false
        self.init(
            id: UUID(),
            url: url,
            bookmark: nil,
            bookmarkIsSecurityScoped: false,
            fileNumber: status.inode,
            volumeID: values?.volumeUUIDString,
            name: values?.name ?? url.lastPathComponent,
            addedAt: addedAt,
            byteCount: status.isDirectory ? nil : status.size,
            contentTypeIdentifier: values?.contentType?.identifier,
            isDirectory: status.isDirectory && !isPackage,
            modifiedAt: values?.contentModificationDate,
            isReadable: FileStatus.isReadable(path: url.path)
        )
        makeBookmark()
    }

    /// Records a bookmark so the item can follow the file after a rename or move.
    /// Security-scoped bookmarks keep the sandbox extension when the file leaves the
    /// watched folder; a plain bookmark is the fallback.
    nonisolated mutating func makeBookmark() {
        if let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmark = data
            bookmarkIsSecurityScoped = true
        } else if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmark = data
            bookmarkIsSecurityScoped = false
        }
    }

    /// Updates cached metadata after the file was found at `newURL`. Returns true if anything changed.
    nonisolated mutating func refresh(at newURL: URL) -> Bool {
        let before = self
        url = newURL.standardizedFileURL
        if let values = try? url.resourceValues(forKeys: Self.resourceKeys) {
            name = values.name ?? url.lastPathComponent
            modifiedAt = values.contentModificationDate
            if let type = values.contentType?.identifier { contentTypeIdentifier = type }
        } else {
            name = url.lastPathComponent
        }
        if let status = FileStatus(path: url.path), !status.isDirectory {
            byteCount = status.size
        }
        isReadable = FileStatus.isReadable(path: url.path)
        return self != before
    }
}

/// Lightweight `lstat` wrapper used by the observer and the collection.
nonisolated struct FileStatus: Equatable, Sendable {
    var inode: UInt64
    var size: Int64
    var modified: TimeInterval
    var created: TimeInterval
    var isDirectory: Bool
    var isSymbolicLink: Bool

    init?(path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        created = TimeInterval(info.st_birthtimespec.tv_sec)
        let type = info.st_mode & S_IFMT
        isDirectory = type == S_IFDIR
        isSymbolicLink = type == S_IFLNK
    }

    static func isReadable(path: String) -> Bool {
        access(path, R_OK) == 0
    }
}
