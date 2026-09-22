import Foundation

/// One file's status in `git status --porcelain=v2`: a staged (index) status
/// character and an unstaged (working tree) status character, per git's own
/// convention (`.` means "no change on this side").
struct GitFileStatus: Equatable, Identifiable {
    var id: String { path }
    let path: String
    let indexStatus: Character
    let workTreeStatus: Character
    let kind: Kind

    enum Kind: Equatable {
        case ordinary, renamed, untracked, unmerged
    }

    var isStaged: Bool { indexStatus != "." && indexStatus != "?" }
}

struct GitBranchStatus: Equatable {
    var branch: String?
    var upstream: String?
    var ahead = 0
    var behind = 0
    var isDetached = false
}

struct GitRepoStatus: Equatable {
    var branchStatus: GitBranchStatus
    var files: [GitFileStatus]

    var isClean: Bool { files.isEmpty }
    var unmergedCount: Int { files.count { $0.kind == .unmerged } }
}

/// Parses `git status --porcelain=v2 --branch` — a stable, documented,
/// script-friendly format (unlike plain `git status`), so this is tested
/// against real captured output rather than against git's human-readable
/// text.
enum GitStatusParser {
    static func parse(_ output: String) -> GitRepoStatus {
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var detached = false
        var files: [GitFileStatus] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.hasPrefix("# branch.head ") {
                let name = String(line.dropFirst("# branch.head ".count))
                if name == "(detached)" { detached = true } else { branch = name }
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                for token in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if token.hasPrefix("+") { ahead = Int(token.dropFirst()) ?? 0 }
                    else if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("1 ") {
                if let entry = ordinaryEntry(line, fieldsBeforePath: 8, kind: .ordinary) { files.append(entry) }
            } else if line.hasPrefix("2 ") {
                if let entry = ordinaryEntry(line, fieldsBeforePath: 9, kind: .renamed) { files.append(renameKeepingNewPath(entry)) }
            } else if line.hasPrefix("u ") {
                if let entry = ordinaryEntry(line, fieldsBeforePath: 10, kind: .unmerged) { files.append(entry) }
            } else if line.hasPrefix("? ") {
                let path = String(line.dropFirst(2))
                files.append(GitFileStatus(path: path, indexStatus: "?", workTreeStatus: "?", kind: .untracked))
            }
        }

        return GitRepoStatus(
            branchStatus: GitBranchStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, isDetached: detached),
            files: files
        )
    }

    /// Shared shape for the "1 XY ... path", "2 XY ... path\torigPath" and
    /// "u XY ... path" record types: an `XY` status pair as the second
    /// field, then a fixed number of fields to skip before the path, which
    /// (unlike everything before it) may itself contain spaces.
    private static func ordinaryEntry(_ line: String, fieldsBeforePath: Int, kind: GitFileStatus.Kind) -> GitFileStatus? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[1].count == 2 else { return nil }
        let xy = parts[1]
        guard let path = dropLeadingFields(fieldsBeforePath, from: Substring(line)) else { return nil }
        return GitFileStatus(path: String(path), indexStatus: xy.first!, workTreeStatus: xy.last!, kind: kind)
    }

    /// A rename record's path is `<new>\t<old>`; only the current path is
    /// worth showing.
    private static func renameKeepingNewPath(_ entry: GitFileStatus) -> GitFileStatus {
        guard let tabIndex = entry.path.firstIndex(of: "\t") else { return entry }
        return GitFileStatus(path: String(entry.path[..<tabIndex]), indexStatus: entry.indexStatus, workTreeStatus: entry.workTreeStatus, kind: entry.kind)
    }

    private static func dropLeadingFields(_ count: Int, from line: Substring) -> Substring? {
        var remainder = line
        for _ in 0..<count {
            guard let spaceIndex = remainder.firstIndex(of: " ") else { return nil }
            remainder = remainder[remainder.index(after: spaceIndex)...]
        }
        return remainder
    }
}

/// Conditions that put the panel into red alert. Being behind a remote
/// isn't alarming on its own — only an actual merge conflict is.
enum GitAlertRules {
    static func reasons(for status: GitRepoStatus) -> [String] {
        let count = status.unmergedCount
        guard count > 0 else { return [] }
        return ["\(count) MERGE CONFLICT\(count == 1 ? "" : "S")"]
    }
}

enum GitStatusFormat {
    static func aheadBehind(_ branch: GitBranchStatus) -> String {
        guard branch.upstream != nil else { return "NO UPSTREAM" }
        if branch.ahead == 0 && branch.behind == 0 { return "UP TO DATE" }
        var parts: [String] = []
        if branch.ahead > 0 { parts.append("\u{2191}\(branch.ahead)") }
        if branch.behind > 0 { parts.append("\u{2193}\(branch.behind)") }
        return parts.joined(separator: " ")
    }

    /// A short, uppercase label for one file's combined status, e.g.
    /// "STAGED", "MODIFIED", "UNTRACKED", "CONFLICT".
    static func label(_ file: GitFileStatus) -> String {
        switch file.kind {
        case .untracked: return "UNTRACKED"
        case .unmerged: return "CONFLICT"
        case .renamed: return file.isStaged ? "RENAMED" : "MODIFIED"
        case .ordinary:
            if file.isStaged && file.workTreeStatus != "." { return "STAGED + MODIFIED" }
            return file.isStaged ? "STAGED" : "MODIFIED"
        }
    }
}
