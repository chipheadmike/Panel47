import SwiftUI

struct ContentView: View {
    @StateObject private var settings: AppSettings
    @StateObject private var store: TerminalSessionStore
    @State private var showingSettings = false

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: TerminalSessionStore(settings: settings))
    }

    var body: some View {
        LCARSChrome(store: store, settings: settings, showingSettings: $showingSettings)
            .frame(minWidth: 900, minHeight: 600)
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings)
            }
    }
}

#Preview {
    ContentView()
}
