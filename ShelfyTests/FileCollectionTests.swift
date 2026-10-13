import XCTest
@testable import Shelfy

/// The basket keeps references only. These tests use real files to check that originals are
/// never touched and that references follow (or let go of) files correctly.
@MainActor
final class FileCollectionTests: XCTestCase {
    private var root: URL!
    private var store: BasketStore!
    private var collection: FileCollection!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ShelfyCollectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = BasketStore(fileURL: root.appending(path: "store/Basket.json"))
        collection = FileCollection(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "locked").path)
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeFile(_ relativePath: String, contents: String = "hello") throws -> URL {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: Originals stay put

    func testClearingTheBasketLeavesOriginalFilesUntouched() throws {
        let urls = try ["a.pdf", "b.png", "c.zip"].map { try makeFile($0, contents: "content of \($0)") }
        urls.forEach { collection.add(fileAt: $0) }
        XCTAssertEqual(collection.items.count, 3)

        collection.clear()

        XCTAssertTrue(collection.items.isEmpty)
        for url in urls {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) was removed")
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "content of \(url.lastPathComponent)")
        }
    }

    func testRemovingAnItemLeavesTheFileUntouched() throws {
        let url = try makeFile("keep-me.txt")
        let item = try XCTUnwrap(collection.add(fileAt: url))
        collection.remove([item.id])
        XCTAssertTrue(collection.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testClearCanBeUndone() throws {
        let first = try makeFile("one.txt")
        let second = try makeFile("two.txt")
        collection.add(fileAt: first)
        collection.add(fileAt: second)
        collection.clear()
        XCTAssertTrue(collection.canUndoClear)
        collection.undoClear()
        XCTAssertEqual(collection.items.map(\.name), ["two.txt", "one.txt"])
        XCTAssertFalse(collection.canUndoClear)
    }

    // MARK: Following files

    func testRenamedFileIsFollowed() throws {
        let url = try makeFile("draft.pdf")
        collection.add(fileAt: url)
        let renamed = root.appending(path: "Final Version.pdf")
        try FileManager.default.moveItem(at: url, to: renamed)

        collection.revalidate()

        XCTAssertEqual(collection.items.count, 1)
        XCTAssertEqual(collection.items.first?.name, "Final Version.pdf")
        XCTAssertEqual(collection.items.first?.url.resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
    }

    func testMovedFileIsFollowed() throws {
        let url = try makeFile("invoice.pdf")
        collection.add(fileAt: url)
        let destination = root.appending(path: "Archive/2026/invoice.pdf")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: destination)

        collection.revalidate()

        XCTAssertEqual(collection.items.first?.url.resolvingSymlinksInPath(), destination.resolvingSymlinksInPath())
    }

    func testDeletedFileIsDropped() throws {
        let url = try makeFile("temporary.txt")
        collection.add(fileAt: url)
        try FileManager.default.removeItem(at: url)
        collection.revalidate()
        XCTAssertTrue(collection.items.isEmpty)
    }

    func testTrashedFileIsDropped() throws {
        let url = try makeFile("unwanted.dmg")
        collection.add(fileAt: url)
        let trash = root.appending(path: ".Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: trash.appending(path: "unwanted.dmg"))
        collection.revalidate()
        XCTAssertTrue(collection.items.isEmpty)
    }

    func testANewFileReusingTheNameIsNotMistakenForTheOriginal() throws {
        let url = try makeFile("report.pdf", contents: "first download")
        collection.add(fileAt: url)
        try FileManager.default.removeItem(at: url)
        try makeFile("report.pdf", contents: "a different download")

        collection.revalidate()

        XCTAssertTrue(collection.items.isEmpty, "the old reference latched onto a different file")
    }

    func testIdenticalNamesInDifferentFoldersAreSeparateItems() throws {
        let first = try makeFile("Downloads A/photo.jpg", contents: "A")
        let second = try makeFile("Downloads B/photo.jpg", contents: "B")
        collection.add(fileAt: first)
        collection.add(fileAt: second)
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertNotEqual(collection.items[0].url, collection.items[1].url)
    }

    func testAddingTheSameFileTwiceMovesItToTheFront() throws {
        let first = try makeFile("first.txt")
        let second = try makeFile("second.txt")
        collection.add(fileAt: first)
        collection.add(fileAt: second)
        collection.add(fileAt: first)
        XCTAssertEqual(collection.items.map(\.name), ["first.txt", "second.txt"])
    }

    func testLosingPermissionKeepsTheReference() throws {
        let url = try makeFile("locked/secret.pdf")
        collection.add(fileAt: url)
        let lockedFolder = root.appending(path: "locked").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedFolder)

        collection.revalidate()

        XCTAssertEqual(collection.items.count, 1, "a permission change isn't a deletion")
        XCTAssertEqual(collection.items.first?.isReadable, false)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedFolder)
        collection.revalidate()
        XCTAssertEqual(collection.items.first?.isReadable, true)
    }

    // MARK: Move to Trash

    /// Points the collection at a scratch Trash so the tests never touch the real one.
    private func useScratchTrash() throws -> URL {
        let trash = root.appending(path: ".Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        collection.trashFile = { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        return trash
    }

    func testMovingToTrashMovesOnlyThatFileAndTakesItOffTheShelf() async throws {
        let trash = try useScratchTrash()
        let keep = try makeFile("keep.txt")
        let unwanted = try makeFile("unwanted.zip", contents: "zip")
        collection.add(fileAt: keep)
        let item = try XCTUnwrap(collection.add(fileAt: unwanted))

        await collection.moveToTrash([item.id])?.value

        XCTAssertEqual(collection.items.map(\.name), ["keep.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: unwanted.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: "unwanted.zip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path), "only the chosen file goes to the Trash")
        XCTAssertTrue(collection.canPutBack)
    }

    func testPutBackRestoresTheFileAndItsPlaceOnTheShelf() async throws {
        _ = try useScratchTrash()
        let urls = try ["one.txt", "two.txt", "three.txt"].map { try makeFile($0, contents: "content of \($0)") }
        urls.forEach { collection.add(fileAt: $0) }
        let middle = try XCTUnwrap(collection.items.first { $0.name == "two.txt" })

        await collection.moveToTrash([middle.id])?.value
        await collection.putBack()?.value

        XCTAssertEqual(collection.items.map(\.name), ["three.txt", "two.txt", "one.txt"])
        XCTAssertEqual(collection.items[1].id, middle.id)
        XCTAssertEqual(try String(contentsOf: urls[1], encoding: .utf8), "content of two.txt")
        XCTAssertFalse(collection.canPutBack)
    }

    func testAFileThatCannotBeTrashedStaysOnTheShelf() async throws {
        collection.trashFile = { _ in throw CocoaError(.fileWriteNoPermission) }
        let url = try makeFile("stubborn.pdf")
        let item = try XCTUnwrap(collection.add(fileAt: url))

        await collection.moveToTrash([item.id])?.value

        XCTAssertEqual(collection.items.map(\.id), [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(collection.notice, .trashFailed)
        XCTAssertFalse(collection.canPutBack)
    }

    func testPutBackNeverReplacesANewFileWithTheSameName() async throws {
        _ = try useScratchTrash()
        let url = try makeFile("report.pdf", contents: "original")
        let item = try XCTUnwrap(collection.add(fileAt: url))
        await collection.moveToTrash([item.id])?.value
        try makeFile("report.pdf", contents: "a newer download")

        await collection.putBack()?.value

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a newer download")
        XCTAssertEqual(collection.notice, .putBackFailed)
    }

    func testUndoFollowsWhicheverActionCameLast() async throws {
        _ = try useScratchTrash()
        collection.add(fileAt: try makeFile("first.txt"))
        let trashed = try XCTUnwrap(collection.add(fileAt: try makeFile("second.txt")))

        await collection.moveToTrash([trashed.id])?.value
        XCTAssertTrue(collection.canUndo)
        collection.clear()
        XCTAssertFalse(collection.canPutBack, "a newer clear replaces the Trash's undo")

        collection.undo()
        XCTAssertEqual(collection.items.map(\.name), ["first.txt"])
    }

    // MARK: Persistence

    func testReferencesSurviveARelaunch() throws {
        let url = try makeFile("survivor.pdf")
        collection.add(fileAt: url)
        collection.saveNow()

        let relaunched = FileCollection(store: store)
        relaunched.load(revalidatingInBackground: false)

        XCTAssertEqual(relaunched.items.map(\.name), ["survivor.pdf"])
        XCTAssertEqual(relaunched.items.first?.fileNumber, collection.items.first?.fileNumber)
    }

    func testRelaunchFollowsAFileMovedWhileQuit() throws {
        let url = try makeFile("moved-while-quit.pdf")
        collection.add(fileAt: url)
        collection.saveNow()
        let destination = root.appending(path: "Elsewhere/moved-while-quit.pdf")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: destination)

        let relaunched = FileCollection(store: store)
        relaunched.load(revalidatingInBackground: false)

        XCTAssertEqual(relaunched.items.first?.url.resolvingSymlinksInPath(), destination.resolvingSymlinksInPath())
    }
}
