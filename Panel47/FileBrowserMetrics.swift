import Foundation

/// One item in a directory listing.
struct FileBrowserEntry: Equatable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    /// nil for directories — showing a directory's total size would mean
    /// recursively scanning it, which is what Cargo Bay is for, not this.
    let sizeBytes: UInt64?
    let modifiedDate: Date?
}

struct FileBrowserError: Equatable, Error {
    let message: String
}

enum FileBrowserMath {
    /// Folders first, then files, each alphabetically — the conventional
    /// Finder-list order.
    static func sorted(_ entries: [FileBrowserEntry]) -> [FileBrowserEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

enum FileBrowserFormat {
    static func size(_ entry: FileBrowserEntry) -> String {
        guard let bytes = entry.sizeBytes else { return "\u{2014}" }
        return StatusFormat.bytes(bytes, style: .file)
    }

    static func modified(_ date: Date?) -> String {
        guard let date else { return "\u{2014}" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date).uppercased()
    }
}
