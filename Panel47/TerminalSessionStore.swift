import Combine
import Foundation

/// Owns every open session and which one(s) are on screen. Sessions are never
/// torn down just because they're not visible — only `close` ends a session.
final class TerminalSessionStore: ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    @Published var primaryID: TerminalSession.ID?
    @Published var secondaryID: TerminalSession.ID?
    @Published private(set) var isSplit = false

    private var nextNumber = 1

    init() {
        newSession()
    }

    @discardableResult
    func newSession() -> TerminalSession {
        let session = addSession()
        primaryID = session.id
        return session
    }

    func toggleSplit() {
        if isSplit {
            isSplit = false
            secondaryID = nil
            return
        }

        let other = sessions.first(where: { $0.id != primaryID }) ?? addSession()
        secondaryID = other.id
        isSplit = true
    }

    @discardableResult
    private func addSession() -> TerminalSession {
        let session = TerminalSession(number: nextNumber)
        nextNumber += 1
        sessions.append(session)
        return session
    }

    func select(_ id: TerminalSession.ID) {
        primaryID = id
    }

    func close(_ id: TerminalSession.ID) {
        sessions.removeAll { $0.id == id }

        if primaryID == id {
            primaryID = sessions.last?.id
        }
        if secondaryID == id {
            secondaryID = sessions.last?.id
            if secondaryID == primaryID {
                secondaryID = sessions.first(where: { $0.id != primaryID })?.id
            }
        }
        if secondaryID == nil {
            isSplit = false
        }
        if sessions.isEmpty {
            newSession()
        }
    }

    func session(for id: TerminalSession.ID?) -> TerminalSession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }
}
