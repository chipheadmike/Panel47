import AppKit
import Combine
import Foundation

/// Lists one directory's immediate contents. Plain `FileManager` calls, not
/// a subprocess — no pty, no pipe, none of the timing pitfalls documented
/// for `du`/`git` elsewhere in this app apply here, since there's no child
/// process at all. Still dispatched off the main thread: a directory with
/// thousands of items (a Photos library, a node_modules) can take a
/// noticeable moment to enumerate.
enum FileBrowserSampler {
    /// Hidden files (dotfiles) are omitted, matching Finder's default view.
    static func listDirectory(_ path: String) -> Result<[FileBrowserEntry], FileBrowserError> {
        let url = URL(fileURLWithPath: path)
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let entries: [FileBrowserEntry] = contents.compactMap { itemURL in
                guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else {
                    return nil
                }
                let isDirectory = values.isDirectory ?? false
                return FileBrowserEntry(
                    name: itemURL.lastPathComponent,
                    path: itemURL.path,
                    isDirectory: isDirectory,
                    sizeBytes: isDirectory ? nil : values.fileSize.map { UInt64($0) },
                    modifiedDate: values.contentModificationDate
                )
            }
            return .success(entries)
        } catch {
            return .failure(FileBrowserError(message: error.localizedDescription))
        }
    }
}

/// Drills into a starting directory one level at a time. A listing is a
/// single synchronous-but-backgrounded `FileManager` call; opening a folder
/// or going up starts a fresh one.
final class FileBrowserModel: ObservableObject {
    let rootPath: String
    @Published private(set) var currentPath: String
    @Published private(set) var entries: [FileBrowserEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var notice: String?

    private var history: [String] = []
    private var hasLoadedOnce = false
    private let lister: (String) -> Result<[FileBrowserEntry], FileBrowserError>
    private let opener: (URL) -> Void
    private let revealer: ([URL]) -> Void
    private let queue = DispatchQueue(label: "panel47.filebrowser", qos: .userInitiated)

    init(
        rootPath: String = NSHomeDirectory(),
        lister: @escaping (String) -> Result<[FileBrowserEntry], FileBrowserError> = FileBrowserSampler.listDirectory,
        opener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        revealer: @escaping ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    ) {
        self.rootPath = rootPath
        self.currentPath = rootPath
        self.lister = lister
        self.opener = opener
        self.revealer = revealer
    }

    var canGoUp: Bool { !history.isEmpty }

    /// Home-relative, for display: `/Users/mike/Documents` -> `~/Documents`.
    var displayPath: String {
        guard currentPath != rootPath else { return "~" }
        guard currentPath.hasPrefix(rootPath + "/") else { return currentPath }
        return "~/" + currentPath.dropFirst(rootPath.count + 1)
    }

    func start() {
        guard !hasLoadedOnce, !isLoading else { return }
        refresh()
    }

    func refresh() {
        isLoading = true
        let path = currentPath
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.lister(path)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentPath == path else { return }
                self.applyListing(result)
            }
        }
    }

    /// Also called directly by tests, bypassing the background dispatch
    /// `refresh()` needs in production.
    func applyListing(_ result: Result<[FileBrowserEntry], FileBrowserError>) {
        hasLoadedOnce = true
        isLoading = false
        switch result {
        case .success(let entries):
            self.entries = FileBrowserMath.sorted(entries)
            notice = nil
        case .failure(let error):
            self.entries = []
            notice = error.message
        }
    }

    /// Drills into a folder, or opens a file with its default application.
    func open(_ entry: FileBrowserEntry) {
        guard entry.isDirectory else {
            opener(URL(fileURLWithPath: entry.path))
            return
        }
        history.append(currentPath)
        currentPath = entry.path
        hasLoadedOnce = false
        refresh()
    }

    func goUp() {
        guard let parent = history.popLast() else { return }
        currentPath = parent
        hasLoadedOnce = false
        refresh()
    }

    func revealCurrentDirectoryInFinder() {
        revealer([URL(fileURLWithPath: currentPath)])
    }
}
