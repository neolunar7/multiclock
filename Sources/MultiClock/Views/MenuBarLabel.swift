import SwiftUI

/// The compact menu bar item: primary clock only, e.g. "NY 10:23".
struct MenuBarLabel: View {
    @ObservedObject private var store = ClockStore.shared
    @ObservedObject private var ticker = Ticker.shared

    var body: some View {
        Text(text)
            // Digits share a width so the item doesn't jitter as the time changes.
            .monospacedDigit()
    }

    private var text: String {
        guard let clock = store.primaryClock else { return "—" }

        let time = TimeFormatting.time(
            ticker.now,
            in: clock,
            use24Hour: store.use24Hour,
            showSeconds: store.showSecondsInMenuBar
        )
        return store.showLabelInMenuBar ? "\(clock.label) \(time)" : time
    }
}
