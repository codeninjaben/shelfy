import Foundation

/// Rules for telling finished downloads apart from the scaffolding browsers leave behind.
nonisolated enum DownloadNaming {
    /// Extensions used for in-progress or partial downloads.
    /// Chrome/Edge/Arc/Brave: .crdownload · Firefox: .part · Safari: .download (a bundle)
    /// Opera: .opdownload · others: .partial .filepart .aria2 .!qb .dtapart .td .bc!
    static let temporaryExtensions: Set<String> = [
        "crdownload", "part", "partial", "download", "opdownload", "filepart",
        "aria2", "!qb", "dtapart", "td", "bc!", "crswap", "tmp", "temp",
    ]

    /// Extensions whose presence next to a file means that file is still being written
    /// (Firefox writes "name.ext.part" and keeps an empty "name.ext" placeholder).
    static let siblingMarkers = ["part", "crdownload", "download", "partial", "opdownload", "filepart", "aria2"]

    /// True for names that should never appear in the basket.
    static func isIgnored(_ name: String) -> Bool {
        if name.isEmpty || name.hasPrefix(".") { return true }          // hidden, .DS_Store, ._AppleDouble, iCloud stubs
        if name.hasPrefix("~$") { return true }                         // Office lock files
        if name == "Icon\r" { return true }                             // custom folder icon file
        if name.range(of: ".sb-", options: .caseInsensitive) != nil {   // sandboxed atomic-save temporaries
            return true
        }
        return isTemporary(name)
    }

    static func isTemporary(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && temporaryExtensions.contains(ext)
    }

    /// Paths that, if present, indicate `name` is still downloading.
    static func siblingMarkerNames(for name: String) -> [String] {
        siblingMarkers.map { "\(name).\($0)" }
    }

    /// The Finder "busy" creation date (1984-01-24 08:00 UTC) that some browsers stamp on
    /// files while they're still being written.
    static let busyCreationDate: TimeInterval = 443_779_200

    static func hasBusyCreationDate(_ status: FileStatus) -> Bool {
        abs(status.created - busyCreationDate) < 86_400
    }
}
