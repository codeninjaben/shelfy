import Foundation

/// Persists basket references (never file contents) as a small JSON document in
/// Application Support, so the basket survives relaunches.
nonisolated struct BasketStore: Sendable {
    let fileURL: URL

    static var standard: BasketStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return BasketStore(fileURL: support.appending(path: "Shelfy", directoryHint: .isDirectory)
            .appending(path: "Basket.json"))
    }

    private struct Payload: Codable {
        var version = 1
        var items: [BasketItem]
    }

    func load() -> [BasketItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode(Payload.self, from: data).items
        } catch {
            Log.app.error("Could not read saved basket: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ items: [BasketItem]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Payload(items: items))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Could not save basket: \(error.localizedDescription, privacy: .public)")
        }
    }
}
