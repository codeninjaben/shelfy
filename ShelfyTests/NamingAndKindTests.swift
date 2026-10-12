import UniformTypeIdentifiers
import XCTest
@testable import Shelfy

final class DownloadNamingTests: XCTestCase {
    func testTemporaryArtifactsAreIgnored() {
        let ignored = [
            "Unconfirmed 123456.crdownload", "report.pdf.crdownload", "photo.jpg.part", "setup.dmg.partial",
            "archive.zip.download", "video.mp4.opdownload", "data.bin.aria2", "movie.mkv.!qB",
            ".DS_Store", ".localized", "._report.pdf", "~$Budget.xlsx", "Icon\r",
            "notes.txt.sb-5f3a2c1b-Ab9xYz", "cache.tmp",
        ]
        for name in ignored {
            XCTAssertTrue(DownloadNaming.isIgnored(name), "\(name) should be ignored")
        }
    }

    func testRealDownloadsAreNotIgnored() {
        let kept = ["report.pdf", "photo.JPG", "Archive.part1.rar", "setup.dmg", "README", "Fonts", "song.m4a",
                    "partial-results.csv", "download.png"]
        for name in kept {
            XCTAssertFalse(DownloadNaming.isIgnored(name), "\(name) should not be ignored")
        }
    }

    func testSiblingMarkersCoverBrowserPartialFiles() {
        let markers = DownloadNaming.siblingMarkerNames(for: "photo.jpg")
        XCTAssertTrue(markers.contains("photo.jpg.part"))
        XCTAssertTrue(markers.contains("photo.jpg.crdownload"))
        XCTAssertTrue(markers.contains("photo.jpg.download"))
    }
}

final class ItemKindTests: XCTestCase {
    private func item(_ name: String, type: UTType?, isDirectory: Bool = false) -> BasketItem {
        BasketItem(id: UUID(), url: URL(fileURLWithPath: "/tmp/\(name)"), bookmark: nil, bookmarkIsSecurityScoped: false,
                   fileNumber: nil, volumeID: nil, name: name, addedAt: .now, byteCount: 1, contentTypeIdentifier: type?.identifier,
                   isDirectory: isDirectory, modifiedAt: nil, isReadable: true)
    }

    func testSummaryUsesTheSharedKind() {
        XCTAssertEqual(ItemKind.summary(for: [item("a.png", type: .png)]), "1 Image")
        XCTAssertEqual(ItemKind.summary(for: [item("a.png", type: .png), item("b.jpg", type: .jpeg)]), "2 Images")
        XCTAssertEqual(ItemKind.summary(for: [item("a.pdf", type: .pdf), item("b.pdf", type: .pdf)]), "2 PDFs")
        XCTAssertEqual(ItemKind.summary(for: [item("Fonts", type: .folder, isDirectory: true)]), "1 Folder")
    }

    func testMixedKindsAreFiles() {
        let mixed = [item("a.png", type: .png), item("b.pdf", type: .pdf), item("c.zip", type: .zip)]
        XCTAssertEqual(ItemKind.summary(for: mixed), "3 Files")
        XCTAssertEqual(ItemKind.summary(for: [item("x.zip", type: .zip)]), "1 Archive")
    }
}

@MainActor
final class PreferencesTests: XCTestCase {
    func testChangesArePersistedAndReported() throws {
        let suite = "ShelfyPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.presentation, .both, "both surfaces by default")
        XCTAssertEqual(preferences.edge, .right)
        XCTAssertEqual(preferences.tabVisibility, .nearPointer, "the tab waits for the pointer by default")
        XCTAssertFalse(preferences.hideTabWhenEmpty)

        var reported: [Preferences.Key] = []
        preferences.onChange = { reported.append($0) }
        preferences.edge = .left
        preferences.verticalPosition = 1.4 // clamped
        preferences.presentation = .menuBar
        preferences.tabVisibility = .always
        preferences.hideTabWhenEmpty = true

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.edge, .left)
        XCTAssertEqual(reloaded.verticalPosition, 1)
        XCTAssertEqual(reloaded.presentation, .menuBar)
        XCTAssertEqual(reloaded.tabVisibility, .always)
        XCTAssertTrue(reloaded.hideTabWhenEmpty)
        XCTAssertTrue(reported.contains(.tabVisibility))
        XCTAssertTrue(reported.contains(.hideTabWhenEmpty))
        XCTAssertTrue(reported.contains(.edge))
        XCTAssertTrue(reported.contains(.verticalPosition))
        XCTAssertTrue(reported.contains(.presentation))
    }
}
