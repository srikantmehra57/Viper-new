import XCTest
@testable import ViperCore

final class StorageScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ViperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testCountsFilesClassifiesAndDoesNotFollowSymbolicLinks() async throws {
        let file = root.appendingPathComponent("notes.txt")
        try Data(repeating: 65, count: 16_384).write(to: file)
        try Data(repeating: 32, count: 8_192).write(to: root.appendingPathComponent("photo.png"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.txt"), withDestinationURL: file)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.files, 2)
        XCTAssertEqual(result.logicalBytes, 24_576)
        XCTAssertEqual(result.skippedLinks, 2)
        XCTAssertEqual(result.largestRootFiles.count, 2)
        XCTAssertNotNil(result.categories[.documents])
        XCTAssertNotNil(result.categories[.images])
        XCTAssertEqual(result.categories.values.reduce(0, +), result.allocatedBytes)
        XCTAssertEqual(try Data(contentsOf: file).count, 16_384, "Scanning must not modify files")
    }

    func testLargestFoldersAggregateImmediateSubfolders() async throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("big/nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("small"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 16_384).write(to: root.appendingPathComponent("big/one.bin"))
        try Data(repeating: 7, count: 8_192).write(to: root.appendingPathComponent("big/nested/two.bin"))
        try Data(repeating: 7, count: 512).write(to: root.appendingPathComponent("small/three.bin"))
        try Data(repeating: 7, count: 128).write(to: root.appendingPathComponent("loose.bin"))
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.largestFolders.map(\.name), ["big", "small"])
        XCTAssertEqual(result.largestFolders.first?.files, 2)
        XCTAssertGreaterThan(result.largestFolders.first?.allocatedBytes ?? 0, result.largestFolders.last?.allocatedBytes ?? 0)
    }

    func testSpaceMapGroupsRemainingFoldersAndLooseFilesWithoutLosingSpace() async throws {
        for index in 1...16 {
            let folder = root.appendingPathComponent("folder-\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: UInt8(index), count: index * 4_096).write(to: folder.appendingPathComponent("data.bin"))
        }
        try Data(repeating: 0, count: 8_192).write(to: root.appendingPathComponent("loose.bin"))
        let result = try await StorageScanner.scan(root: root)
        let items = result.mapItems
        XCTAssertEqual(result.largestFolders.count, 12)
        XCTAssertEqual(items.count, 7)
        XCTAssertEqual(items.compactMap(\.url), Array(result.largestFolders.prefix(6).map(\.url)))
        XCTAssertEqual(items.reduce(Int64(0)) { $0 + $1.allocatedBytes }, result.allocatedBytes)
        XCTAssertEqual(items.reduce(0) { $0 + $1.files }, result.files)
        XCTAssertEqual(items.last?.name, "Other files & folders")
        XCTAssertNil(items.last?.url)
        XCTAssertEqual(items.last?.files, result.files - result.largestFolders.prefix(6).reduce(0) { $0 + $1.files })
    }

    func testSpaceMapLeavesASingleFolderAvailableToExplore() async throws {
        let folder = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: folder.appendingPathComponent("file.txt"))
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.mapItems.count, 1)
        XCTAssertEqual(result.mapItems[0].url, result.largestFolders[0].url)
        XCTAssertEqual(result.mapItems[0].kind, .folder)
        XCTAssertEqual(result.mapItems[0].allocatedBytes, result.allocatedBytes)
    }

    func testSpaceMapShowsFilesAtTheRootWithoutInventingFolders() async throws {
        let file = root.appendingPathComponent("loose.bin")
        try Data(repeating: 1, count: 8_192).write(to: file)
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.mapItems.count, 1)
        XCTAssertEqual(result.mapItems[0].name, "loose.bin")
        XCTAssertEqual(result.mapItems[0].kind, .file)
        XCTAssertEqual(result.mapItems[0].url, result.root.appendingPathComponent(file.lastPathComponent))
        XCTAssertEqual(result.mapItems[0].allocatedBytes, result.allocatedBytes)
    }

    func testSpaceMapShowsLargeLooseFilesAlongsideFolders() async throws {
        let folder = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: folder.appendingPathComponent("notes.txt"))
        let movie = root.appendingPathComponent("movie.mov")
        try Data(repeating: 2, count: 65_536).write(to: movie)
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.mapItems.first?.url, result.root.appendingPathComponent(movie.lastPathComponent))
        XCTAssertEqual(result.mapItems.first?.kind, .file)
        XCTAssertTrue(result.mapItems.contains { $0.url == result.root.appendingPathComponent(folder.lastPathComponent) && $0.kind == .folder })
        XCTAssertEqual(result.mapItems.reduce(Int64(0)) { $0 + $1.allocatedBytes }, result.allocatedBytes)
    }

    func testSpaceMapBoundsLooseFilesWithoutLosingTheRest() async throws {
        for index in 1...9 {
            try Data(repeating: UInt8(index), count: index * 4_096).write(to: root.appendingPathComponent("loose-\(index).bin"))
        }
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.largestRootFiles.count, 6)
        XCTAssertEqual(result.mapItems.count, 7)
        XCTAssertEqual(result.mapItems.first?.name, "loose-9.bin")
        XCTAssertEqual(result.mapItems.first?.kind, .file)
        XCTAssertNil(result.mapItems.last?.url)
        XCTAssertEqual(result.mapItems.reduce(Int64(0)) { $0 + $1.allocatedBytes }, result.allocatedBytes)
        XCTAssertEqual(result.mapItems.reduce(0) { $0 + $1.files }, result.files)
    }

    func testHardLinksCountOnce() async throws {
        let file = root.appendingPathComponent("original.bin")
        try Data(repeating: 12, count: 16_384).write(to: file)
        try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("hardlink.bin"))
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.files, 1)
        XCTAssertEqual(result.duplicateHardLinks, 1)
        XCTAssertEqual(result.logicalBytes, 16_384)
    }

    func testLargestFilesAreBoundedAndSorted() async throws {
        for index in 1...110 {
            try Data(repeating: UInt8(index), count: index * 4_096).write(to: root.appendingPathComponent("file-\(index).txt"))
        }
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.files, 110)
        XCTAssertEqual(result.largestFiles.count, 100)
        let sizes = result.largestFiles.map(\.allocatedBytes)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
    }

    func testScanSummaryRoundTripsWithoutTheFileList() async throws {
        try Data(repeating: 1, count: 8_192).write(to: root.appendingPathComponent("notes.txt"))
        let result = try await StorageScanner.scan(root: root)
        let url = root.appendingPathComponent("summary.json")
        try result.summary.save(to: url)
        let loaded = StoredScanSummary.load(from: url)
        XCTAssertEqual(loaded?.root, result.root.path)
        XCTAssertEqual(loaded?.files, 1)
        XCTAssertEqual(loaded?.allocatedBytes, result.allocatedBytes)
        XCTAssertEqual(loaded?.largestFolders, [])
    }

    func testEmptyFolder() async throws {
        let result = try await StorageScanner.scan(root: root)
        XCTAssertEqual(result.files, 0)
        XCTAssertEqual(result.allocatedBytes, 0)
        XCTAssertTrue(result.largestFiles.isEmpty)
        XCTAssertTrue(result.largestRootFiles.isEmpty)
        XCTAssertTrue(result.mapItems.isEmpty)
        XCTAssertFalse(result.hasLimitedCoverage)
    }

    func testCancellationNeverReturnsCompletedScan() async throws {
        let folder = root!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await StorageScanner.scan(root: folder)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }

    func testSymlinkRootRejected() async throws {
        let link = root.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        do {
            _ = try await StorageScanner.scan(root: link)
            XCTFail("A symbolic-link root should be rejected")
        } catch { }
    }

    func testMissingFolderThrows() async throws {
        do {
            _ = try await StorageScanner.scan(root: root.appendingPathComponent("missing"))
            XCTFail("Expected a missing-folder error")
        } catch { }
    }

    func testClassificationUsesPathComponents() {
        XCTAssertEqual(StorageCategory.classify(URL(fileURLWithPath: "/App.app/Contents/file"), relativePath: "App.app/Contents/file"), .applications)
        XCTAssertEqual(StorageCategory.classify(URL(fileURLWithPath: "/node_modules/a/index.json"), relativePath: "node_modules/a/index.json"), .development)
        XCTAssertEqual(StorageCategory.classify(URL(fileURLWithPath: "/notnode_modules/file.json"), relativePath: "notnode_modules/file.json"), .other)
    }
}
