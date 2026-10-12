import XCTest
@testable import Shelfy

/// Exercises the observer against real files, replaying the on-disk sequences browsers
/// and command-line tools produce.
final class DownloadObserverTests: XCTestCase {
    private var folder: URL!
    private var observer: DownloadObserver?
    private var recorder: EventRecorder!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "ShelfyObserverTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        recorder = EventRecorder()
    }

    override func tearDownWithError() throws {
        observer?.stop()
        observer = nil
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Helpers

    private func startObserver(_ configure: (inout DownloadObserver.Options) -> Void = { _ in }) {
        var options = DownloadObserver.Options()
        options.settleInterval = 0.6
        options.pollInterval = 0.15
        options.emptyFileGrace = 2
        configure(&options)
        let recorder = recorder!
        let observer = DownloadObserver(folder: folder, options: options) { event in recorder.record(event) }
        observer.start()
        self.observer = observer
        Thread.sleep(forTimeInterval: 0.4) // let the stream come up before files change
    }

    private func url(_ name: String) -> URL { folder.appending(path: name) }

    private func write(_ name: String, bytes: Int = 4096) throws {
        try Data(repeating: 0x2A, count: bytes).write(to: url(name))
    }

    /// Appends in chunks with pauses shorter than the settle interval, like a live transfer.
    private func stream(_ name: String, chunks: Int, pause: TimeInterval = 0.25) throws {
        if !FileManager.default.fileExists(atPath: url(name).path) {
            FileManager.default.createFile(atPath: url(name).path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url(name))
        defer { try? handle.close() }
        for _ in 0..<chunks {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(repeating: 0x41, count: 64 * 1024))
            Thread.sleep(forTimeInterval: pause)
        }
    }

    private func rename(_ from: String, _ to: String) throws {
        try FileManager.default.moveItem(at: url(from), to: url(to))
    }

    private func waitForReadyNames(count: Int, timeout: TimeInterval = 6) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, recorder.readyNames.count < count {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return recorder.readyNames
    }

    private func assertNoReadyEvents(for seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: seconds)
        XCTAssertEqual(recorder.readyNames, [], "expected no completed downloads", file: file, line: line)
    }

    // MARK: First launch

    func testExistingFilesAreNotReported() throws {
        try write("already-here.pdf")
        try write("old-photo.jpg")
        startObserver()
        assertNoReadyEvents(for: 1.5)
    }

    // MARK: Completed downloads

    func testDirectWriteIsReportedOnceAfterItSettles() throws {
        startObserver()
        let started = Date()
        try stream("curl-download.zip", chunks: 6)
        let finishedWriting = Date()
        XCTAssertEqual(waitForReadyNames(count: 1), ["curl-download.zip"])
        let reportedAt = recorder.firstReadyDate ?? .distantPast
        XCTAssertGreaterThan(reportedAt, finishedWriting, "reported while bytes were still arriving")
        XCTAssertGreaterThan(finishedWriting.timeIntervalSince(started), 1.2)
        assertNoReadyEvents(after: 1)
    }

    func testChromeStyleDownloadIsReportedUnderItsFinalName() throws {
        startObserver()
        try write("Unconfirmed 81723.crdownload", bytes: 1024)
        try stream("Unconfirmed 81723.crdownload", chunks: 3)
        try rename("Unconfirmed 81723.crdownload", "Quarterly Report.pdf.crdownload")
        try stream("Quarterly Report.pdf.crdownload", chunks: 3)
        XCTAssertEqual(recorder.readyNames, [], "partial download surfaced early")
        try rename("Quarterly Report.pdf.crdownload", "Quarterly Report.pdf")
        XCTAssertEqual(waitForReadyNames(count: 1), ["Quarterly Report.pdf"])
        assertNoReadyEvents(after: 1)
    }

    func testFirefoxStylePlaceholderWaitsForThePartFile() throws {
        startObserver()
        FileManager.default.createFile(atPath: url("photo.jpg").path, contents: nil) // empty placeholder
        try stream("photo.jpg.part", chunks: 12) // ~3 s, longer than the empty-file grace period
        XCTAssertEqual(recorder.readyNames, [], "placeholder surfaced while .part was still downloading")
        // Firefox finishes with rename(2) over the placeholder.
        XCTAssertEqual(Darwin.rename(url("photo.jpg.part").path, url("photo.jpg").path), 0)
        XCTAssertEqual(waitForReadyNames(count: 1), ["photo.jpg"])
        let size = try XCTUnwrap(FileStatus(path: url("photo.jpg").path)?.size)
        XCTAssertGreaterThan(size, 0)
    }

    func testSafariStyleBundleIsReportedWhenTheFileMovesOut() throws {
        startObserver()
        let bundle = url("Design Assets.zip.download")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try stream("Design Assets.zip.download/Design Assets.zip", chunks: 4)
        XCTAssertEqual(recorder.readyNames, [])
        try FileManager.default.moveItem(at: bundle.appending(path: "Design Assets.zip"), to: url("Design Assets.zip"))
        try FileManager.default.removeItem(at: bundle)
        XCTAssertEqual(waitForReadyNames(count: 1), ["Design Assets.zip"])
    }

    func testSeveralDownloadsAreEachReportedOnce() throws {
        startObserver()
        for index in 1...3 {
            try write("file-\(index).png.crdownload", bytes: 2048)
        }
        for index in 1...3 {
            try rename("file-\(index).png.crdownload", "file-\(index).png")
        }
        try stream("notes.txt", chunks: 2)
        let names = waitForReadyNames(count: 4)
        XCTAssertEqual(Set(names), ["file-1.png", "file-2.png", "file-3.png", "notes.txt"])
        XCTAssertEqual(names.count, 4, "a download was reported more than once")
    }

    func testDownloadedFolderIsReported() throws {
        startObserver()
        let staging = folder.appending(path: ".extracting")
        try FileManager.default.createDirectory(at: staging.appending(path: "Fonts"), withIntermediateDirectories: true)
        try Data(count: 512).write(to: staging.appending(path: "Fonts/Inter.ttf"))
        try FileManager.default.moveItem(at: staging, to: url("Inter Family"))
        XCTAssertEqual(waitForReadyNames(count: 1), ["Inter Family"])
    }

    // MARK: Interrupted downloads

    func testInterruptedChromeDownloadNeverAppears() throws {
        startObserver()
        try write("Unconfirmed 5512.crdownload")
        try rename("Unconfirmed 5512.crdownload", "big-video.mp4.crdownload")
        try stream("big-video.mp4.crdownload", chunks: 3)
        // The transfer stops here; the browser leaves the partial file behind.
        assertNoReadyEvents(for: 2)
        try FileManager.default.removeItem(at: url("big-video.mp4.crdownload")) // user cancels
        assertNoReadyEvents(for: 1)
    }

    func testInterruptedFirefoxDownloadNeverAppears() throws {
        startObserver()
        FileManager.default.createFile(atPath: url("setup.dmg").path, contents: nil)
        try stream("setup.dmg.part", chunks: 3)
        // Stalled: the empty placeholder must stay hidden while its .part sibling exists.
        assertNoReadyEvents(for: 3)
    }

    func testInterruptedSafariDownloadNeverAppears() throws {
        startObserver()
        let bundle = url("dataset.csv.download")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try stream("dataset.csv.download/dataset.csv", chunks: 3)
        assertNoReadyEvents(for: 2)
    }

    // MARK: Things that aren't downloads

    func testRenamingAnExistingFileIsNotADownload() throws {
        try write("draft.txt")
        startObserver()
        try rename("draft.txt", "final.txt")
        assertNoReadyEvents(for: 1.5)
    }

    func testModifyingAnExistingFileIsNotADownload() throws {
        try write("journal.md")
        startObserver()
        try stream("journal.md", chunks: 2)
        assertNoReadyEvents(for: 1.5)
    }

    func testTemporaryAndHiddenFilesAreIgnored() throws {
        startObserver()
        try write(".DS_Store")
        try write("~$Budget.xlsx")
        try write("cache.tmp")
        try write("Report.pdf.sb-1a2b3c4d-QwErTy")
        try write("movie.mkv.part")
        assertNoReadyEvents(for: 1.5)
    }

    // MARK: Relaunch catch-up

    func testCatchUpReportsFilesAddedSinceTheWatermark() throws {
        try write("arrived-while-quit.pdf")
        startObserver { $0.catchUpSince = Date().addingTimeInterval(-60) }
        XCTAssertEqual(waitForReadyNames(count: 1), ["arrived-while-quit.pdf"])
        XCTAssertEqual(recorder.catchUpFlags, [true])
    }

    func testCatchUpIgnoresFilesOlderThanTheWatermark() throws {
        try write("old-news.pdf")
        Thread.sleep(forTimeInterval: 1.1)
        startObserver { $0.catchUpSince = Date() }
        assertNoReadyEvents(for: 1.5)
    }

    private func assertNoReadyEvents(after seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let before = recorder.readyNames
        Thread.sleep(forTimeInterval: seconds)
        XCTAssertEqual(recorder.readyNames, before, "unexpected extra events", file: file, line: line)
    }
}

/// Thread-safe sink for observer events (they arrive on the observer's queue).
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ready: [(name: String, date: Date, isCatchUp: Bool)] = []

    func record(_ event: DownloadObserver.Event) {
        guard case .fileReady(let url, let isCatchUp) = event else { return }
        lock.withLock { ready.append((url.lastPathComponent, Date(), isCatchUp)) }
    }

    var readyNames: [String] { lock.withLock { ready.map(\.name) } }
    var firstReadyDate: Date? { lock.withLock { ready.first?.date } }
    var catchUpFlags: [Bool] { lock.withLock { ready.map(\.isCatchUp) } }
}
