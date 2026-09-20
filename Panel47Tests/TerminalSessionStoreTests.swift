import Foundation
import Testing
@testable import Panel47

@MainActor
struct TerminalSessionStoreTests {
    private func makeStore() -> TerminalSessionStore {
        let suiteName = "Panel47Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return TerminalSessionStore(settings: AppSettings(defaults: defaults))
    }

    @Test func startsWithOneSessionSelected() {
        let store = makeStore()
        #expect(store.sessions.count == 1)
        #expect(store.primaryID == store.sessions.first?.id)
        #expect(store.isSplit == false)
    }

    @Test func newSessionIsAddedAndSelected() {
        let store = makeStore()
        let second = store.newSession()
        #expect(store.sessions.count == 2)
        #expect(store.primaryID == second.id)
    }

    @Test func toggleSplitPicksADifferentSecondarySession() {
        let store = makeStore()
        let first = store.primaryID

        store.toggleSplit()

        #expect(store.isSplit)
        #expect(store.sessions.count == 2)
        #expect(store.primaryID == first) // splitting shouldn't move the current session out of primary
        #expect(store.secondaryID != nil)
        #expect(store.secondaryID != first)

        store.toggleSplit()

        #expect(store.isSplit == false)
        #expect(store.secondaryID == nil)
    }

    @Test func closingPrimaryFallsBackToAnotherSession() {
        let store = makeStore()
        let first = store.primaryID!
        let second = store.newSession()

        store.close(second.id)

        #expect(store.sessions.count == 1)
        #expect(store.primaryID == first)
    }

    @Test func closingLastSessionAlwaysLeavesOneBehind() {
        let store = makeStore()
        let only = store.primaryID!

        store.close(only)

        #expect(store.sessions.count == 1)
        #expect(store.primaryID != nil)
        #expect(store.primaryID != only)
    }

    @Test func closingSecondaryEndsSplit() {
        let store = makeStore()
        store.toggleSplit()
        let secondary = store.secondaryID!

        store.close(secondary)

        #expect(store.isSplit == false)
        #expect(store.secondaryID == nil)
    }
}
