import SwiftUI

struct ContentView: View {
    @StateObject private var store = TerminalSessionStore()

    var body: some View {
        LCARSChrome(store: store)
            .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
