import Foundation
import Testing
@testable import Panel47

struct GitStatusParserTests {
    @Test func aCleanUntrackedRepoParses() {
        // Real capture: `git status --porcelain=v2 --branch` right after `git init`, one file staged and modified.
        let output = """
        # branch.oid 9b8281c90f1a428cfd20e99cc510c5ce08d769a9
        # branch.head main
        1 .M N... 100644 100644 100644 ce013625030ba8dba906f756967f9e9ca394464a ce013625030ba8dba906f756967f9e9ca394464a a.txt
        ? b.txt
        """
        let status = GitStatusParser.parse(output)
        #expect(status.branchStatus.branch == "main")
        #expect(status.branchStatus.upstream == nil)
        #expect(status.branchStatus.ahead == 0 && status.branchStatus.behind == 0)
        #expect(status.files.count == 2)
        let modified = try? #require(status.files.first { $0.path == "a.txt" })
        #expect(modified?.kind == .ordinary)
        #expect(modified?.indexStatus == "." && modified?.workTreeStatus == "M")
        #expect(modified?.isStaged == false)
        let untracked = try? #require(status.files.first { $0.path == "b.txt" })
        #expect(untracked?.kind == .untracked)
    }

    @Test func aheadOfUpstreamParses() {
        // Real capture: local commit made after pushing to origin/main.
        let output = """
        # branch.oid ae0a820c1dbf39906b8629ee9602006d88dc3315
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +1 -0
        ? x.txt
        """
        let status = GitStatusParser.parse(output)
        #expect(status.branchStatus.upstream == "origin/main")
        #expect(status.branchStatus.ahead == 1)
        #expect(status.branchStatus.behind == 0)
    }

    @Test func behindUpstreamParses() {
        // Real capture: a fresh clone after the remote moved ahead.
        let output = """
        # branch.oid c91711f35d8d912fb9e254751fa9bfeff08c9936
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -1
        """
        #expect(GitStatusParser.parse(output).branchStatus.behind == 1)
    }

    @Test func aRenameKeepsOnlyTheNewPath() {
        // Real capture: `git mv a.txt renamed.txt`, staged.
        let output = """
        # branch.oid ae0a820c1dbf39906b8629ee9602006d88dc3315
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        2 R. N... 100644 100644 100644 94954abda49de8615a048f8d2e64b5de848e27a1 94954abda49de8615a048f8d2e64b5de848e27a1 R100 renamed.txt\ta.txt
        ? x.txt
        """
        let status = GitStatusParser.parse(output)
        let renamed = try? #require(status.files.first { $0.kind == .renamed })
        #expect(renamed?.path == "renamed.txt")
        #expect(renamed?.path.contains("\t") == false)
    }

    @Test func detachedHeadIsRecognized() {
        let output = "# branch.oid abc\n# branch.head (detached)\n"
        let status = GitStatusParser.parse(output)
        #expect(status.branchStatus.isDetached)
        #expect(status.branchStatus.branch == nil)
    }

    @Test func anUnmergedConflictParses() {
        // Per git's documented porcelain v2 format (10 fields before path for
        // the "u" record type), not independently captured live.
        let output = "u UU N... 100644 100644 100644 100644 <h1> <h2> <h3> conflict.txt"
        let status = GitStatusParser.parse(output)
        let file = try? #require(status.files.first)
        #expect(file?.kind == .unmerged)
        #expect(file?.path == "conflict.txt")
        #expect(status.unmergedCount == 1)
    }

    @Test func garbageAndBlankLinesAreIgnored() {
        #expect(GitStatusParser.parse("").files.isEmpty)
        #expect(GitStatusParser.parse("not a status line\n\n").files.isEmpty)
    }

    @Test func isCleanReflectsAnEmptyFileList() {
        #expect(GitStatusParser.parse("# branch.head main\n").isClean)
        #expect(!GitStatusParser.parse("# branch.head main\n? a\n").isClean)
    }
}

struct GitAlertRulesTests {
    @Test func noConflictsRaisesNoAlert() {
        let status = GitRepoStatus(branchStatus: GitBranchStatus(), files: [])
        #expect(GitAlertRules.reasons(for: status).isEmpty)
    }

    @Test func conflictsAreCountedNotJustFlagged() {
        let files = [
            GitFileStatus(path: "a", indexStatus: "U", workTreeStatus: "U", kind: .unmerged),
            GitFileStatus(path: "b", indexStatus: "U", workTreeStatus: "U", kind: .unmerged),
            GitFileStatus(path: "c", indexStatus: ".", workTreeStatus: "M", kind: .ordinary),
        ]
        let status = GitRepoStatus(branchStatus: GitBranchStatus(), files: files)
        #expect(GitAlertRules.reasons(for: status) == ["2 MERGE CONFLICTS"])
    }

    @Test func beingBehindIsNotAnAlert() {
        let status = GitRepoStatus(branchStatus: GitBranchStatus(branch: "main", behind: 5), files: [])
        #expect(GitAlertRules.reasons(for: status).isEmpty)
    }
}

struct GitStatusFormatTests {
    @Test func aheadBehindFormatsAllFourStates() {
        #expect(GitStatusFormat.aheadBehind(GitBranchStatus(upstream: nil)) == "NO UPSTREAM")
        #expect(GitStatusFormat.aheadBehind(GitBranchStatus(upstream: "origin/main", ahead: 0, behind: 0)) == "UP TO DATE")
        #expect(GitStatusFormat.aheadBehind(GitBranchStatus(upstream: "origin/main", ahead: 2, behind: 0)) == "\u{2191}2")
        #expect(GitStatusFormat.aheadBehind(GitBranchStatus(upstream: "origin/main", ahead: 0, behind: 3)) == "\u{2193}3")
        #expect(GitStatusFormat.aheadBehind(GitBranchStatus(upstream: "origin/main", ahead: 1, behind: 2)) == "\u{2191}1 \u{2193}2")
    }

    @Test func fileLabelsCoverEveryKind() {
        #expect(GitStatusFormat.label(GitFileStatus(path: "a", indexStatus: ".", workTreeStatus: "M", kind: .ordinary)) == "MODIFIED")
        #expect(GitStatusFormat.label(GitFileStatus(path: "a", indexStatus: "M", workTreeStatus: ".", kind: .ordinary)) == "STAGED")
        #expect(GitStatusFormat.label(GitFileStatus(path: "a", indexStatus: "M", workTreeStatus: "M", kind: .ordinary)) == "STAGED + MODIFIED")
        #expect(GitStatusFormat.label(GitFileStatus(path: "a", indexStatus: "?", workTreeStatus: "?", kind: .untracked)) == "UNTRACKED")
        #expect(GitStatusFormat.label(GitFileStatus(path: "a", indexStatus: "U", workTreeStatus: "U", kind: .unmerged)) == "CONFLICT")
        #expect(GitStatusFormat.label(GitFileStatus(path: "a", indexStatus: "R", workTreeStatus: ".", kind: .renamed)) == "RENAMED")
    }
}

@MainActor
struct TacticalModelTests {
    private func status(clean: Bool) -> GitRepoStatus {
        GitRepoStatus(
            branchStatus: GitBranchStatus(branch: "main"),
            files: clean ? [] : [GitFileStatus(path: "a", indexStatus: ".", workTreeStatus: "M", kind: .ordinary)]
        )
    }

    @Test func startCallsTheStatusReaderExactlyOnce() {
        var callCount = 0
        let model = TacticalModel(directory: "/tmp", statusReader: { _, _ in callCount += 1 })
        model.start()
        model.start() // a second call while a read is already pending must not fire another
        #expect(callCount == 1)
    }

    @Test func applyStatusPopulatesFromTheReading() {
        let model = TacticalModel(directory: "/tmp", statusReader: { _, _ in })
        model.applyStatus(status(clean: true))
        #expect(model.status != nil)
        #expect(model.notice == nil)
    }

    @Test func pullIsRefusedOnADirtyTree() {
        let model = TacticalModel(directory: "/tmp", statusReader: { _, _ in })
        model.applyStatus(status(clean: false))
        model.pull()
        #expect(model.notice == "PULL REFUSED \u{00B7} WORKING TREE NOT CLEAN")
    }

    @Test func aFailedStatusReadShowsANotice() {
        let model = TacticalModel(directory: "/tmp", statusReader: { _, _ in })
        model.applyStatus(nil)
        #expect(model.status == nil)
        #expect(model.notice == "COULD NOT READ REPOSITORY STATUS")
    }
}

/// These run the real `git` binary against real repositories this test
/// creates, so they check real end-to-end behavior rather than only
/// hand-written porcelain text.
struct LiveGitSamplerTests {
    private func makeRepo() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tactical-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try run("/usr/bin/git", ["init", "-q"], in: root)
        try run("/usr/bin/git", ["config", "user.email", "test@test.com"], in: root)
        try run("/usr/bin/git", ["config", "user.name", "test"], in: root)
        return root
    }

    @discardableResult
    private func run(_ path: String, _ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test func aRealRepositoryIsDetected() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        #expect(GitSampler.isRepository(directory: repo.path))
    }

    @Test func aPlainDirectoryIsNotDetected() throws {
        let notARepo = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: notARepo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notARepo) }
        #expect(!GitSampler.isRepository(directory: notARepo.path))
    }

    @Test func readStatusReflectsARealUntrackedFile() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try Data("hello".utf8).write(to: repo.appendingPathComponent("new.txt"))

        let status: GitRepoStatus? = await withCheckedContinuation { continuation in
            GitSampler.readStatus(directory: repo.path) { continuation.resume(returning: $0) }
        }
        let files = try #require(status).files
        #expect(files.map(\.path) == ["new.txt"])
        #expect(files[0].kind == .untracked)
    }

    @Test func readStatusReflectsARealStagedFile() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try Data("hello".utf8).write(to: repo.appendingPathComponent("staged.txt"))
        try run("/usr/bin/git", ["add", "staged.txt"], in: repo)

        let status: GitRepoStatus? = await withCheckedContinuation { continuation in
            GitSampler.readStatus(directory: repo.path) { continuation.resume(returning: $0) }
        }
        let files = try #require(status).files
        let file = try #require(files.first)
        #expect(file.isStaged)
        #expect(GitStatusFormat.label(file) == "STAGED")
    }
}
