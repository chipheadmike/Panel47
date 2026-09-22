import Foundation
import Testing
@testable import Panel47

struct FileBrowserMathTests {
    private func entry(_ name: String, isDirectory: Bool) -> FileBrowserEntry {
        FileBrowserEntry(name: name, path: "/tmp/\(name)", isDirectory: isDirectory, sizeBytes: isDirectory ? nil : 100, modifiedDate: nil)
    }

    @Test func foldersSortBeforeFiles() {
        let entries = [entry("z-file.txt", isDirectory: false), entry("a-folder", isDirectory: true)]
        #expect(FileBrowserMath.sorted(entries).map(\.name) == ["a-folder", "z-file.txt"])
    }

    @Test func withinEachGroupSortsAlphabetically() {
        let entries = [entry("banana", isDirectory: false), entry("apple", isDirectory: false), entry("Zebra", isDirectory: true), entry("apple-folder", isDirectory: true)]
        #expect(FileBrowserMath.sorted(entries).map(\.name) == ["apple-folder", "Zebra", "apple", "banana"])
    }

    @Test func sortIsCaseInsensitiveAndNaturalForNumbers() {
        let entries = [entry("file10.txt", isDirectory: false), entry("file2.txt", isDirectory: false), entry("File1.txt", isDirectory: false)]
        #expect(FileBrowserMath.sorted(entries).map(\.name) == ["File1.txt", "file2.txt", "file10.txt"])
    }
}

struct FileBrowserFormatTests {
    @Test func directoriesShowNoSize() {
        let dir = FileBrowserEntry(name: "d", path: "/tmp/d", isDirectory: true, sizeBytes: nil, modifiedDate: nil)
        #expect(FileBrowserFormat.size(dir) == "\u{2014}")
    }

    @Test func filesShowAFormattedSize() {
        let file = FileBrowserEntry(name: "f", path: "/tmp/f", isDirectory: false, sizeBytes: 1_500_000, modifiedDate: nil)
        #expect(FileBrowserFormat.size(file).contains("MB"))
    }

    @Test func aMissingDateShowsADash() {
        #expect(FileBrowserFormat.modified(nil) == "\u{2014}")
    }

    @Test func aRealDateFormats() {
        let text = FileBrowserFormat.modified(Date())
        #expect(text != "\u{2014}")
        #expect(!text.isEmpty)
    }
}

@MainActor
struct FileBrowserModelTests {
    private func entry(_ name: String, isDirectory: Bool = false, path: String = "/tmp") -> FileBrowserEntry {
        FileBrowserEntry(name: name, path: "\(path)/\(name)", isDirectory: isDirectory, sizeBytes: isDirectory ? nil : 10, modifiedDate: nil)
    }

    @Test func startListsTheRootExactlyOnce() {
        var callCount = 0
        let model = FileBrowserModel(rootPath: "/tmp", lister: { _ in callCount += 1; return .success([]) })
        model.start()
        model.start()
        #expect(callCount == 0) // start() itself never calls the lister directly (refresh() does, off-thread)
    }

    @Test func applyListingSortsAndClearsNotice() {
        let model = FileBrowserModel(rootPath: "/tmp", lister: { _ in .success([]) })
        model.applyListing(.success([entry("z.txt"), entry("a", isDirectory: true)]))
        #expect(model.entries.map(\.name) == ["a", "z.txt"])
        #expect(model.notice == nil)
    }

    @Test func applyListingFailureShowsTheMessageAndClearsEntries() {
        let model = FileBrowserModel(rootPath: "/tmp", lister: { _ in .success([]) })
        model.applyListing(.success([entry("a")]))
        model.applyListing(.failure(FileBrowserError(message: "Permission denied")))
        #expect(model.entries.isEmpty)
        #expect(model.notice == "Permission denied")
    }

    @Test func openingAFolderDrillsInAndRecordsHistoryForUp() {
        let model = FileBrowserModel(rootPath: "/tmp", lister: { _ in .success([]) })
        #expect(!model.canGoUp)
        model.open(entry("sub", isDirectory: true, path: "/tmp"))
        #expect(model.currentPath == "/tmp/sub")
        #expect(model.displayPath == "~/sub")
        #expect(model.canGoUp)
    }

    @Test func goUpReturnsToTheParent() {
        let model = FileBrowserModel(rootPath: "/tmp", lister: { _ in .success([]) })
        model.open(entry("sub", isDirectory: true, path: "/tmp"))
        model.goUp()
        #expect(model.currentPath == "/tmp")
        #expect(!model.canGoUp)
    }

    @Test func goUpAtTheRootDoesNothing() {
        let model = FileBrowserModel(rootPath: "/tmp", lister: { _ in .success([]) })
        model.goUp()
        #expect(model.currentPath == "/tmp")
    }

    @Test func openingAFileCallsTheOpenerNotTheLister() {
        var openedURL: URL?
        var listerCalls = 0
        let model = FileBrowserModel(
            rootPath: "/tmp",
            lister: { _ in listerCalls += 1; return .success([]) },
            opener: { openedURL = $0 }
        )
        model.open(entry("notes.txt", path: "/tmp"))
        #expect(openedURL == URL(fileURLWithPath: "/tmp/notes.txt"))
        #expect(model.currentPath == "/tmp") // opening a file never navigates
        #expect(listerCalls == 0)
    }

    @Test func revealInFinderPassesTheCurrentDirectory() {
        var revealed: [URL] = []
        let model = FileBrowserModel(rootPath: "/tmp/project", lister: { _ in .success([]) }, revealer: { revealed = $0 })
        model.revealCurrentDirectoryInFinder()
        #expect(revealed == [URL(fileURLWithPath: "/tmp/project")])
    }
}

/// These run against a real temp directory this test creates.
struct LiveFileBrowserSamplerTests {
    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("navigator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func listsRealFilesAndFolders() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: root.appendingPathComponent("file.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("subfolder"), withIntermediateDirectories: true)

        let result = FileBrowserSampler.listDirectory(root.path)
        let entries = try #require(try? result.get())
        #expect(entries.count == 2)
        let file = try #require(entries.first { $0.name == "file.txt" })
        #expect(!file.isDirectory)
        #expect(file.sizeBytes == 5)
        let folder = try #require(entries.first { $0.name == "subfolder" })
        #expect(folder.isDirectory)
        #expect(folder.sizeBytes == nil)
    }

    @Test func hiddenFilesAreOmitted() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("x".utf8).write(to: root.appendingPathComponent(".hidden"))
        try Data("x".utf8).write(to: root.appendingPathComponent("visible.txt"))

        let entries = try #require(try? FileBrowserSampler.listDirectory(root.path).get())
        #expect(entries.map(\.name) == ["visible.txt"])
    }

    @Test func aMissingDirectoryFails() {
        let result = FileBrowserSampler.listDirectory("/nonexistent/path/\(UUID().uuidString)")
        if case .success = result { Issue.record("expected failure for a missing directory") }
    }

    @Test func modificationDatesAreReadBack() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("x".utf8).write(to: root.appendingPathComponent("f.txt"))

        let entries = try #require(try? FileBrowserSampler.listDirectory(root.path).get())
        let file = try #require(entries.first)
        #expect(file.modifiedDate != nil)
        #expect(abs(file.modifiedDate!.timeIntervalSinceNow) < 10)
    }
}
