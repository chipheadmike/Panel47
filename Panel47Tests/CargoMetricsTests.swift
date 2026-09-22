import Foundation
import Testing
@testable import Panel47

struct CargoParserTests {
    @Test func aLineParsesIntoKilobytesAndPath() {
        let parsed = try? #require(CargoParser.parseLine("128\t/Users/mike/Documents"))
        #expect(parsed?.path == "/Users/mike/Documents")
        #expect(parsed?.bytes == 128 * 1024)
    }

    @Test func garbageLinesDoNotParse() {
        #expect(CargoParser.parseLine("") == nil)
        #expect(CargoParser.parseLine("du: /Users/mike/Photos: Operation not permitted") == nil)
        #expect(CargoParser.parseLine("not-a-number\t/Users/mike") == nil)
        #expect(CargoParser.parseLine("128") == nil)
    }

    @Test func aRealDuSLineBecomesAnEntry() {
        // A real line from `du -s -k`.
        let entry = try? #require(CargoParser.singleEntry(fromLine: "177663436\t/Users/mikewilliams/Library"))
        #expect(entry?.name == "Library")
        #expect(entry?.path == "/Users/mikewilliams/Library")
        #expect(entry?.bytes == 177_663_436 * 1024)
    }

    @Test func aGarbageLineYieldsNoEntry() {
        #expect(CargoParser.singleEntry(fromLine: "du: /Users/mike/Photos: Operation not permitted") == nil)
        #expect(CargoParser.singleEntry(fromLine: "") == nil)
    }
}

struct CargoMathTests {
    private func entry(_ name: String, _ bytes: UInt64) -> CargoEntry {
        CargoEntry(name: name, path: "/Users/mike/\(name)", bytes: bytes)
    }

    @Test func topSortsLargestFirst() {
        let entries = [entry("a", 100), entry("b", 900), entry("c", 500)]
        #expect(CargoMath.top(entries, limit: 10).map(\.name) == ["b", "c", "a"])
    }

    @Test func topIsLimited() {
        let entries = (0..<20).map { entry("f\($0)", UInt64($0)) }
        #expect(CargoMath.top(entries, limit: 5).count == 5)
    }

    @Test func tiesBreakByName() {
        let entries = [entry("zebra", 100), entry("apple", 100)]
        #expect(CargoMath.top(entries, limit: 10).map(\.name) == ["apple", "zebra"])
    }

    @Test func fractionScalesAgainstTheLargestEntry() {
        #expect(CargoMath.fraction(for: entry("a", 50), scale: 100) == 0.5)
        #expect(CargoMath.fraction(for: entry("a", 100), scale: 100) == 1)
        #expect(CargoMath.fraction(for: entry("a", 500), scale: 100) == 1) // clamped
        #expect(CargoMath.fraction(for: entry("a", 1), scale: 0) == 0)
    }

    @Test func totalBytesSumsEverything() {
        let entries = [entry("a", 100), entry("b", 200)]
        #expect(CargoMath.totalBytes(entries) == 300)
    }
}

@MainActor
struct CargoModelTests {
    /// A stand-in scan function: records every path it was asked to scan
    /// and hands back a cancel closure that records whether it was called.
    /// Nothing is delivered to `onEntry`/`completion` unless the test does
    /// it explicitly, which keeps these tests synchronous.
    final class ScanSpy {
        private(set) var scannedPaths: [String] = []
        private(set) var cancelCallCount = 0

        func makeFunction() -> CargoScanFunction {
            { [weak self] path, _, _ in
                self?.scannedPaths.append(path)
                return { self?.cancelCallCount += 1 }
            }
        }
    }

    @Test func startScansTheRootExactlyOnce() {
        let spy = ScanSpy()
        let model = CargoModel(rootPath: "/Users/mike", scan: spy.makeFunction())
        model.start()
        model.start() // a second call while nothing has changed must not rescan
        #expect(spy.scannedPaths == ["/Users/mike"])
        #expect(model.isScanning)
    }

    @Test func discoveredEntriesAccumulateInOrder() {
        let model = CargoModel(rootPath: "/Users/mike", scan: ScanSpy().makeFunction())
        model.start()
        model.applyDiscovered(CargoEntry(name: "Documents", path: "/Users/mike/Documents", bytes: 100))
        model.applyDiscovered(CargoEntry(name: "Library", path: "/Users/mike/Library", bytes: 900))
        #expect(model.entries.map(\.name) == ["Documents", "Library"])
        model.applyScanFinished(hadSkippedItems: true)
        #expect(!model.isScanning)
        #expect(model.hadSkippedItems)
    }

    @Test func openDrillsInAndRecordsHistoryForUp() {
        let spy = ScanSpy()
        let model = CargoModel(rootPath: "/Users/mike", scan: spy.makeFunction())
        model.start()
        model.applyDiscovered(CargoEntry(name: "Library", path: "/Users/mike/Library", bytes: 900))
        model.applyScanFinished(hadSkippedItems: false)

        #expect(!model.canGoUp)
        model.open(CargoEntry(name: "Library", path: "/Users/mike/Library", bytes: 900))
        #expect(model.currentPath == "/Users/mike/Library")
        #expect(model.displayPath == "~/Library")
        #expect(model.canGoUp)
        #expect(spy.scannedPaths == ["/Users/mike", "/Users/mike/Library"])
        // Opening a folder starts a fresh scan: the old results are gone.
        #expect(model.entries.isEmpty)
        #expect(model.isScanning)
    }

    @Test func goUpReturnsToTheParentAndRescans() {
        let spy = ScanSpy()
        let model = CargoModel(rootPath: "/Users/mike", scan: spy.makeFunction())
        model.start()
        model.applyScanFinished(hadSkippedItems: false)
        model.open(CargoEntry(name: "Library", path: "/Users/mike/Library", bytes: 900))
        model.applyScanFinished(hadSkippedItems: false)

        model.goUp()
        #expect(model.currentPath == "/Users/mike")
        #expect(!model.canGoUp)
        #expect(spy.scannedPaths == ["/Users/mike", "/Users/mike/Library", "/Users/mike"])
    }

    @Test func goUpAtTheRootDoesNothing() {
        let spy = ScanSpy()
        let model = CargoModel(rootPath: "/Users/mike", scan: spy.makeFunction())
        model.start()
        model.goUp()
        #expect(spy.scannedPaths == ["/Users/mike"])
        #expect(model.currentPath == "/Users/mike")
    }

    @Test func rescanCancelsAnInFlightScanBeforeStartingAnother() {
        let spy = ScanSpy()
        let model = CargoModel(rootPath: "/Users/mike", scan: spy.makeFunction())
        model.start()
        model.rescan()
        #expect(spy.scannedPaths == ["/Users/mike", "/Users/mike"])
        #expect(spy.cancelCallCount == 1)
    }

    @Test func stopCancelsAndClearsPartialResults() {
        let spy = ScanSpy()
        let model = CargoModel(rootPath: "/Users/mike", scan: spy.makeFunction())
        model.start()
        model.applyDiscovered(CargoEntry(name: "Documents", path: "/Users/mike/Documents", bytes: 100))

        model.stop()
        #expect(spy.cancelCallCount == 1)
        #expect(model.entries.isEmpty)
        #expect(!model.isScanning)

        // Coming back starts a genuinely fresh scan, not a no-op.
        model.start()
        #expect(spy.scannedPaths == ["/Users/mike", "/Users/mike"])
    }

    @Test func resultsFromAStalePathAreIgnored() {
        // Simulates a slow first scan whose entry arrives after the user has
        // already drilled into a different folder.
        var capturedOnEntry: ((CargoEntry) -> Void)?
        let scan: CargoScanFunction = { path, onEntry, _ in
            if path == "/Users/mike" { capturedOnEntry = onEntry }
            return {}
        }
        let model = CargoModel(rootPath: "/Users/mike", scan: scan)
        model.start()
        model.open(CargoEntry(name: "Library", path: "/Users/mike/Library", bytes: 900))
        capturedOnEntry?(CargoEntry(name: "Documents", path: "/Users/mike/Documents", bytes: 100))
        #expect(model.entries.isEmpty)
    }
}

/// These run the real `du` on real directories this test creates, so they
/// check relative sizes and shape rather than exact byte counts (the
/// filesystem rounds each file up to its allocation block size).
struct LiveCargoScannerTests {
    private func makeTempTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cargo-\(UUID().uuidString)")
        let big = root.appendingPathComponent("big")
        let small = root.appendingPathComponent("small")
        try FileManager.default.createDirectory(at: big, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: small, withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: big.appendingPathComponent("file.bin"))
        try Data(count: 50_000).write(to: small.appendingPathComponent("file.bin"))
        return root
    }

    @Test func aRealScanFindsBothFoldersWithTheBiggerOneLarger() async throws {
        let root = try makeTempTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let entries: [CargoEntry] = try await withCheckedThrowingContinuation { continuation in
            var found: [CargoEntry] = []
            CargoScanner.scan(path: root.path, onEntry: { found.append($0) }, completion: { _ in
                continuation.resume(returning: found)
            })
        }

        #expect(Set(entries.map(\.name)) == ["big", "small"])
        let big = try #require(entries.first { $0.name == "big" })
        let small = try #require(entries.first { $0.name == "small" })
        #expect(big.bytes > small.bytes)
        #expect(big.bytes >= 2_000_000)
    }

    @Test func cancellingStopsFurtherDeliveries() async throws {
        let root = try makeTempTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let cancel = CargoScanner.scan(path: root.path, onEntry: { _ in }, completion: { _ in })
        cancel() // must not crash even though the scan may already be finishing
    }

    @Test func aPermissionDeniedFolderIsSkippedNotShownAsEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cargo-\(UUID().uuidString)")
        let locked = root.appendingPathComponent("locked")
        let open = root.appendingPathComponent("open")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: open.appendingPathComponent("file.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }

        let (entries, hadSkippedItems): ([CargoEntry], Bool) = await withCheckedContinuation { continuation in
            var found: [CargoEntry] = []
            CargoScanner.scan(path: root.path, onEntry: { found.append($0) }, completion: { skipped in
                continuation.resume(returning: (found, skipped))
            })
        }

        #expect(entries.map(\.name) == ["open"]) // the locked folder produces no du line at all
        #expect(hadSkippedItems)
    }

    /// Regression test for a real deadlock: `du` writes one warning line per
    /// permission-denied child to stderr as it recurses, and if nothing
    /// reads that pipe while the process is still running, enough of them
    /// fill the kernel pipe buffer and `du` blocks inside `write()` forever.
    /// This reproduces it with one directory holding far more
    /// permission-denied children than fit in any realistic pipe buffer.
    @Test func manyPermissionErrorsInOneDuCallDoNotDeadlockTheScan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cargo-\(UUID().uuidString)")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let lockedCount = 1000
        for index in 0..<lockedCount {
            let locked = target.appendingPathComponent("locked\(index)")
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        }
        defer {
            for index in 0..<lockedCount {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.appendingPathComponent("locked\(index)").path)
            }
            try? FileManager.default.removeItem(at: root)
        }

        final class Box: @unchecked Sendable {
            var entries: [CargoEntry] = []
            var hadSkippedItems = false
        }
        let box = Box()

        let finishedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    CargoScanner.scan(
                        path: root.path,
                        onEntry: { box.entries.append($0) },
                        completion: { skipped in
                            box.hadSkippedItems = skipped
                            continuation.resume()
                        }
                    )
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // generous, but nowhere near "forever"
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        #expect(finishedInTime, "scan did not finish within 15s — likely deadlocked on a full stderr pipe")
        #expect(box.entries.map(\.name) == ["target"])
        #expect(box.hadSkippedItems)
    }

    @Test func moreChildrenThanTheConcurrencyCapAreAllEventuallyReported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cargo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let childCount = CargoScanner.maxConcurrent * 2 + 1
        for index in 0..<childCount {
            let child = root.appendingPathComponent("folder\(index)")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            try Data(count: 1_000).write(to: child.appendingPathComponent("file.bin"))
        }

        let entries: [CargoEntry] = await withCheckedContinuation { continuation in
            var found: [CargoEntry] = []
            CargoScanner.scan(path: root.path, onEntry: { found.append($0) }, completion: { _ in
                continuation.resume(returning: found)
            })
        }

        #expect(entries.count == childCount)
        #expect(Set(entries.map(\.name)).count == childCount)
    }
}
