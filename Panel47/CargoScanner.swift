import Combine
import Foundation

/// A running (or finished) scan's cancel handle.
typealias CargoCancel = () -> Void

/// A function shaped like `CargoScanner.scan`, injectable for tests.
typealias CargoScanFunction = (
    _ path: String,
    _ onEntry: @escaping (CargoEntry) -> Void,
    _ completion: @escaping (_ hadSkippedItems: Bool) -> Void
) -> CargoCancel

/// Measures every immediate subdirectory of `path` with its own small
/// `du -s -x -k <child>` call, a few at a time, and reports each one as it
/// finishes. A single `du -d 1` over the whole directory would be one
/// process instead of many, but macOS fully buffers a non-terminal pipe:
/// nothing arrives until that one process's internal buffer fills or it
/// exits, so a large home directory would sit at "0 found" for the entire
/// scan. Many small per-directory processes trade that for real, honest
/// progress — each is cheap, and finishes independently. `-x` keeps each
/// one on a single filesystem, so a mounted network share doesn't turn a
/// scan into a very long one.
enum CargoScanner {
    static let maxConcurrent = 4

    @discardableResult
    static func scan(
        path: String,
        onEntry: @escaping (CargoEntry) -> Void,
        completion: @escaping (_ hadSkippedItems: Bool) -> Void
    ) -> CargoCancel {
        let children: [String]
        do {
            children = try FileManager.default
                .contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
                .compactMap { url -> String? in
                    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          values.isDirectory == true, values.isSymbolicLink != true else { return nil }
                    return url.path
                }
        } catch {
            completion(false)
            return {}
        }

        guard !children.isEmpty else {
            completion(false)
            return {}
        }

        let batch = CargoBatch(children: children, onEntry: onEntry, completion: completion)
        batch.start()
        return { batch.cancelAll() }
    }
}

/// Runs up to `CargoScanner.maxConcurrent` `du -s` subprocesses at once over
/// a fixed list of directories, filling a new slot each time one finishes.
/// All the bookkeeping (what's queued, what's running, whether we've been
/// cancelled) is confined to `queue` so it's safe to touch from the
/// termination handlers, which fire on arbitrary threads.
private final class CargoBatch {
    private let children: [String]
    private let onEntry: (CargoEntry) -> Void
    private let completion: (Bool) -> Void

    private let queue = DispatchQueue(label: "panel47.cargo.batch")
    private var nextIndex = 0
    private var runningCount = 0
    private var hadSkippedItems = false
    private var cancelled = false
    private var activeProcesses: Set<Process> = []

    init(children: [String], onEntry: @escaping (CargoEntry) -> Void, completion: @escaping (Bool) -> Void) {
        self.children = children
        self.onEntry = onEntry
        self.completion = completion
    }

    func start() {
        queue.async { self.fillSlots() }
    }

    func cancelAll() {
        queue.async {
            self.cancelled = true
            for process in self.activeProcesses where process.isRunning {
                process.terminationHandler = nil
                process.terminate()
            }
            self.activeProcesses.removeAll()
        }
    }

    /// Must only be called on `queue`.
    private func fillSlots() {
        guard !cancelled else { return }
        while runningCount < CargoScanner.maxConcurrent, nextIndex < children.count {
            launch(children[nextIndex])
            nextIndex += 1
            runningCount += 1
        }
        if !cancelled, runningCount == 0, nextIndex >= children.count {
            completion(hadSkippedItems)
        }
    }

    /// Must only be called on `queue`.
    private func launch(_ childPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-s", "-x", "-k", childPath]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        activeProcesses.insert(process)

        do {
            try process.run()
        } catch {
            activeProcesses.remove(process)
            runningCount -= 1
            fillSlots()
            return
        }

        // A directory with many TCC-protected children (Library is the
        // worst offender) makes `du` write one warning line per one to
        // stderr. Nothing reads that pipe until the process exits, so if
        // those warnings ever exceed the kernel pipe buffer, `du` blocks
        // inside write() forever — a real deadlock, not a slow scan.
        // Reading both pipes to EOF concurrently, rather than only after
        // the process terminates, is what prevents that; `readToEnd()`
        // handles the actual draining, so there's no hand-rolled buffering
        // or ordering to get wrong. This `Task` captures `self` (this
        // batch) strongly, deliberately: nothing else is guaranteed to
        // keep it alive between launching a process and it finishing.
        // No `waitUntilExit()` here: it blocks its calling thread, and with
        // several of these Tasks running at once that can starve Swift's
        // cooperative thread pool badly enough to stall the whole scan.
        // Both pipes reaching EOF already means the child is done writing
        // to them, which is all the data path needs; Foundation reaps the
        // process on its own once it has actually exited.
        Task {
            async let outRead = try? outPipe.fileHandleForReading.readToEnd()
            async let errRead = try? errPipe.fileHandleForReading.readToEnd()
            let outData = await outRead
            let hadStderr = await errRead?.isEmpty == false

            let line = outData.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\n").first
            let entry = line.flatMap { CargoParser.singleEntry(fromLine: String($0)) }

            self.queue.async {
                self.activeProcesses.remove(process)
                guard !self.cancelled else { return }
                if hadStderr { self.hadSkippedItems = true }
                self.runningCount -= 1
                if let entry { self.onEntry(entry) }
                self.fillSlots()
            }
        }
    }
}

/// Drills into the user's home directory one level at a time. A scan is a
/// single pass over the current level; opening a folder or going up starts a
/// fresh one. Leaving the panel cancels whatever is in flight and clears its
/// partial results, so coming back always shows a complete scan rather than
/// a stale, half-finished one.
final class CargoModel: ObservableObject {
    static let rowLimit = 10

    let rootPath: String
    @Published private(set) var currentPath: String
    @Published private(set) var entries: [CargoEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var hadSkippedItems = false

    private var history: [String] = []
    private var cancelCurrentScan: CargoCancel?
    private let scan: CargoScanFunction

    init(rootPath: String = NSHomeDirectory(), scan: @escaping CargoScanFunction = CargoScanner.scan) {
        self.rootPath = rootPath
        self.currentPath = rootPath
        self.scan = scan
    }

    var canGoUp: Bool { !history.isEmpty }

    /// Home-relative, for display: `/Users/mike/Library` -> `~/Library`.
    var displayPath: String {
        guard currentPath != rootPath else { return "~" }
        guard currentPath.hasPrefix(rootPath + "/") else { return currentPath }
        return "~/" + currentPath.dropFirst(rootPath.count + 1)
    }

    func start() {
        guard entries.isEmpty, !isScanning else { return }
        beginScan()
    }

    func stop() {
        cancelCurrentScan?()
        cancelCurrentScan = nil
        isScanning = false
        entries = []
        hadSkippedItems = false
    }

    func rescan() {
        beginScan()
    }

    func open(_ entry: CargoEntry) {
        history.append(currentPath)
        currentPath = entry.path
        beginScan()
    }

    func goUp() {
        guard let parent = history.popLast() else { return }
        currentPath = parent
        beginScan()
    }

    private func beginScan() {
        cancelCurrentScan?()
        entries = []
        hadSkippedItems = false
        isScanning = true

        let path = currentPath
        cancelCurrentScan = scan(
            path,
            { [weak self] entry in
                DispatchQueue.main.async {
                    guard let self, self.currentPath == path else { return }
                    self.applyDiscovered(entry)
                }
            },
            { [weak self] hadSkipped in
                DispatchQueue.main.async {
                    guard let self, self.currentPath == path else { return }
                    self.applyScanFinished(hadSkippedItems: hadSkipped)
                }
            }
        )
    }

    // MARK: - Applying results (main thread; also called directly by tests)

    func applyDiscovered(_ entry: CargoEntry) {
        entries.append(entry)
    }

    func applyScanFinished(hadSkippedItems: Bool) {
        isScanning = false
        cancelCurrentScan = nil
        self.hadSkippedItems = hadSkippedItems
    }
}
