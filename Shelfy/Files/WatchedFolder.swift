import AppKit
import Observation

/// The folder Shelfy watches: the user's Downloads folder by default (sandbox Downloads
/// entitlement plus the system's privacy consent) or a folder the user picked (kept with a
/// security-scoped bookmark).
///
/// Access checks never run on the main thread: the first touch of a protected folder can
/// block until the user answers the system's privacy prompt, and the tab should appear
/// immediately regardless.
@MainActor @Observable
final class WatchedFolder {
    enum Status: Equatable, Sendable { case available, accessDenied, missing }

    private(set) var url: URL
    private(set) var isDefault: Bool
    /// Optimistic until the first background check completes.
    private(set) var status: Status = .available

    /// Called when the folder itself changes (not its contents).
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when access is gained or lost.
    @ObservationIgnored var onStatusChange: ((Status) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var checkGeneration = 0
    private static let bookmarkKey = "Shelfy.watchedFolderBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        url = Self.downloadsURL
        isDefault = true
        resolveStoredFolder()
    }

    /// The real `~/Downloads`. Inside the sandbox `FileManager` reports the container's
    /// home directory, so ask the user database instead.
    nonisolated static var downloadsURL: URL {
        realHomeDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    nonisolated static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    var displayName: String {
        isDefault ? "Downloads" : url.lastPathComponent
    }

    var icon: NSImage {
        let downloadsIcon = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/DownloadsFolder.icns"
        if isDefault, let image = NSImage(contentsOfFile: downloadsIcon) { return image }
        return NSWorkspace.shared.icon(for: .folder)
    }

    // MARK: Choosing

    /// Shows an open panel. Picking a folder there is what grants the sandboxed app access.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Watch Folder"
        panel.message = "Choose the folder where new downloads arrive."
        panel.directoryURL = url
        NSApp.activate()
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        use(chosen)
    }

    func useDownloads() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        stopAccessing()
        apply(url: Self.downloadsURL, isDefault: true)
    }

    /// Re-checks access in the background and reports a change through `onStatusChange`.
    func refreshStatus() {
        checkGeneration += 1
        let generation = checkGeneration
        let folder = url
        Task.detached(priority: .utility) { [weak self] in
            let latest = Self.status(of: folder)
            await self?.publish(latest, generation: generation, folder: folder)
        }
    }

    private func publish(_ latest: Status, generation: Int, folder: URL) {
        guard generation == checkGeneration, folder == url, latest != status else { return }
        status = latest
        onStatusChange?(latest)
    }

    // MARK: Private

    private func use(_ chosen: URL) {
        let standardized = chosen.standardizedFileURL
        guard let bookmark = try? standardized.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                           includingResourceValuesForKeys: nil, relativeTo: nil) else {
            Log.app.error("Could not create a bookmark for the chosen folder")
            return
        }
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        stopAccessing()
        if standardized.startAccessingSecurityScopedResource() { scopedURL = standardized }
        let isDownloads = standardized.resolvingSymlinksInPath().path == Self.downloadsURL.resolvingSymlinksInPath().path
        apply(url: standardized, isDefault: isDownloads)
    }

    private func resolveStoredFolder() {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                      relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            Log.app.error("Saved folder bookmark could not be resolved; falling back to Downloads")
            return
        }
        if resolved.startAccessingSecurityScopedResource() { scopedURL = resolved }
        if isStale, let fresh = try? resolved.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                          includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        url = resolved
        isDefault = resolved.resolvingSymlinksInPath().path == Self.downloadsURL.resolvingSymlinksInPath().path
    }

    private func apply(url newURL: URL, isDefault newIsDefault: Bool) {
        url = newURL
        isDefault = newIsDefault
        status = .available
        onChange?()
        refreshStatus()
    }

    private func stopAccessing() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private nonisolated static func status(of folder: URL) -> Status {
        guard let directory = opendir(folder.path) else {
            return (errno == EACCES || errno == EPERM) ? .accessDenied : .missing
        }
        closedir(directory)
        return .available
    }
}
