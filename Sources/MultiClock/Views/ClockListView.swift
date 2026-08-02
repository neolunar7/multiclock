import SwiftUI

/// The dropdown panel: every configured clock with full detail.
struct ClockListView: View {
    @ObservedObject private var store = ClockStore.shared
    @ObservedObject private var ticker = Ticker.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.clocks.isEmpty {
                emptyState
            } else {
                ForEach(store.clocks) { clock in
                    ClockRow(clock: clock, now: ticker.now, use24Hour: store.use24Hour, showSeconds: store.showSecondsInPanel)
                }
            }

            Divider().padding(.vertical, 6)

            footer
        }
        .padding(12)
        .frame(width: 268)
    }

    private var emptyState: some View {
        Text("No clocks yet — add one in Settings.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            PanelButton(title: "Settings…", shortcut: "⌘,") {
                // An LSUIElement app has no Dock presence, so the settings window opens
                // behind whatever is frontmost unless we explicitly activate first.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            PanelButton(title: "Quit MultiClock", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct ClockRow: View {
    let clock: Clock
    let now: Date
    let use24Hour: Bool
    let showSeconds: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(clock.label)
                    .font(.system(size: 13, weight: .medium))
                Text(TimeFormatting.relativeOffsetDescription(now, in: clock))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(TimeFormatting.time(now, in: clock, use24Hour: use24Hour, showSeconds: showSeconds))
                .font(.system(size: 13, weight: .regular))
                .monospacedDigit()

            HStack(spacing: 1) {
                Text(TimeFormatting.weekday(now, in: clock))
                if let badge = TimeFormatting.dayOffsetBadge(now, in: clock) {
                    Text(badge)
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            // Reserve the widest case ("Wed+1") so times stay column-aligned
            // whether or not a row carries a day badge.
            .frame(width: 38, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// Menu-style row button: no chrome until hovered, matching the system menu look.
private struct PanelButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(isHovering ? .white.opacity(0.7) : .secondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(isHovering ? .white : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? Color.accentColor : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
