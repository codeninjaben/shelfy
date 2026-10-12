import AppKit
import QuickLookThumbnailing

nonisolated struct Thumbnail: @unchecked Sendable {
    let image: NSImage
    /// True when Quick Look could only offer the file's icon (archives, disk images, …).
    /// Icons are drawn as-is; real previews get rounded corners and a shadow.
    let isIcon: Bool
}

/// Generates and caches Quick Look thumbnails. Everything stays on device.
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private struct Key: Hashable {
        let id: UUID
        let modified: Date?
        let pixelSide: Int
    }

    private var cache: [Key: Thumbnail] = [:]
    private var recency: [Key] = []
    private var inFlight: [Key: Task<Thumbnail?, Never>] = [:]
    private var icons: [UUID: Thumbnail] = [:]
    private let cacheLimit = 240

    /// A cached preview at least as large as requested, if one exists.
    func cachedThumbnail(for item: BasketItem, side: CGFloat, scale: CGFloat) -> Thumbnail? {
        let wanted = Int(side * scale)
        if let exact = cache[Key(id: item.id, modified: item.modifiedAt, pixelSide: wanted)] { return exact }
        return cache.first { $0.key.id == item.id && $0.key.modified == item.modifiedAt && $0.key.pixelSide >= wanted }?.value
    }

    /// The file's Finder icon, available synchronously as a placeholder.
    func iconThumbnail(for item: BasketItem) -> Thumbnail {
        if let icon = icons[item.id] { return icon }
        let icon = Thumbnail(image: NSWorkspace.shared.icon(forFile: item.url.path), isIcon: true)
        icons[item.id] = icon
        return icon
    }

    /// The best image available right now, for drag images and Quick Look transitions.
    func bestAvailableImage(for item: BasketItem) -> Thumbnail {
        let candidates = cache.filter { $0.key.id == item.id && $0.key.modified == item.modifiedAt }
        if let best = candidates.max(by: { $0.key.pixelSide < $1.key.pixelSide })?.value { return best }
        return iconThumbnail(for: item)
    }

    func thumbnail(for item: BasketItem, side: CGFloat, scale: CGFloat) async -> Thumbnail? {
        let key = Key(id: item.id, modified: item.modifiedAt, pixelSide: Int(side * scale))
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }
        let url = item.url
        let task = Task.detached(priority: .userInitiated) {
            await Self.generate(url: url, side: side, scale: scale)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { remember(result, for: key) }
        return result
    }

    func forget(_ ids: Set<UUID>) {
        cache = cache.filter { !ids.contains($0.key.id) }
        recency.removeAll { ids.contains($0.id) }
        ids.forEach { icons[$0] = nil }
    }

    private func remember(_ thumbnail: Thumbnail, for key: Key) {
        cache[key] = thumbnail
        recency.removeAll { $0 == key }
        recency.append(key)
        while recency.count > cacheLimit {
            cache[recency.removeFirst()] = nil
        }
    }

    private nonisolated static func generate(url: URL, side: CGFloat, scale: CGFloat) async -> Thumbnail? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: scale, representationTypes: .all)
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return Thumbnail(image: representation.nsImage, isIcon: representation.type == .icon)
        } catch {
            return nil
        }
    }
}
