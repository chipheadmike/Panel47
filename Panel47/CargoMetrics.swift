import Foundation

/// One immediate child directory of the path being scanned, as `du` reports
/// it: its own size plus everything inside it, recursively.
struct CargoEntry: Equatable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let bytes: UInt64
}

/// Parses the plain, tab-separated output of `du -k`. Kept apart from the
/// process that runs `du` so it can be tested against real captured output
/// without touching the filesystem.
enum CargoParser {
    /// One line: `"<kilobytes>\t<path>"`.
    static func parseLine(_ line: String) -> (path: String, bytes: UInt64)? {
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2, let kilobytes = UInt64(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (String(parts[1]), kilobytes * 1024)
    }

    /// A `du -s` line for a single directory we already know is a child of
    /// wherever we're scanning, so unlike a `du -d 1` capture there's no
    /// "total for the root itself" line to filter out.
    static func singleEntry(fromLine line: String) -> CargoEntry? {
        guard let (path, bytes) = parseLine(line) else { return nil }
        return CargoEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes)
    }
}

enum CargoMath {
    /// Largest first; ties broken by name so the order is stable.
    static func top(_ entries: [CargoEntry], limit: Int) -> [CargoEntry] {
        Array(
            entries
                .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
                .prefix(limit)
        )
    }

    /// Fraction of `scale` (typically the largest entry on screen), for
    /// sizing a bar. 0 when there's nothing to compare against.
    static func fraction(for entry: CargoEntry, scale: UInt64) -> Double {
        scale > 0 ? min(1, Double(entry.bytes) / Double(scale)) : 0
    }

    static func totalBytes(_ entries: [CargoEntry]) -> UInt64 {
        entries.reduce(0) { $0 + $1.bytes }
    }
}
