import SwiftUI

@main
struct MultiClockApp: App {
    @ObservedObject private var store = ClockStore.shared

    init() {
        // Match the tick rate to what's actually displayed, before the first render.
        Ticker.shared.needsSecondResolution =
            ClockStore.shared.showSecondsInMenuBar || ClockStore.shared.showSecondsInPanel
    }

    var body: some Scene {
        MenuBarExtra {
            ClockListView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
