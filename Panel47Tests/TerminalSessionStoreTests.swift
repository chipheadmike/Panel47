import Testing
@testable import Panel47

@MainActor
struct TerminalSessionStoreTests {
    @Test func startsWithOneSessionSelected() {
        let store = TerminalSessionStore()
        #expect(store.sessions.count == 1)
        #expect(store.primaryID == store.sessions.first?.id)
        #expect(store.isSplit == false)
    }

    @Test func newSessionIsAddedAndSelected() {
        let store = TerminalSessionStore()
        let second = store.newSession()
        #expect(store.sessions.count == 2)
        #expect(store.primaryID == second.id)
    }

    @Test func toggleSplitPicksADifferentSecondarySession() {
        let store = TerminalSessionStore()
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
        let store = TerminalSessionStore()
        let first = store.primaryID!
        let second = store.newSession()

        store.close(second.id)

        #expect(store.sessions.count == 1)
        #expect(store.primaryID == first)
    }

    @Test func closingLastSessionAlwaysLeavesOneBehind() {
        let store = TerminalSessionStore()
        let only = store.primaryID!

        store.close(only)

        #expect(store.sessions.count == 1)
        #expect(store.primaryID != nil)
        #expect(store.primaryID != only)
    }

    @Test func closingSecondaryEndsSplit() {
        let store = TerminalSessionStore()
        store.toggleSplit()
        let secondary = store.secondaryID!

        store.close(secondary)

        #expect(store.isSplit == false)
        #expect(store.secondaryID == nil)
    }
}
