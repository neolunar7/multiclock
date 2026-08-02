import SwiftUI

/// The dropdown panel: every configured clock, either live or at a planned instant.
struct ClockListView: View {
    @ObservedObject private var store = ClockStore.shared
    @ObservedObject private var ticker = Ticker.shared
    @ObservedObject private var planning = PlanningState.shared
    @Environment(\.openSettings) private var openSettings

    /// Live time, or the planned instant when planning.
    private var displayedInstant: Date {
        planning.isPlanning ? planning.instant : ticker.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modePicker

            if planning.isPlanning {
                planningHeader
            }

            if store.clocks.isEmpty {
                emptyState
            } else {
                rows
            }

            Divider().padding(.vertical, 6)

            footer
        }
        .padding(12)
        .frame(width: 300)
        // Reset on every appearance: a planned time must never be mistaken for the
        // real one just because the panel was left in that state earlier.
        .onAppear { planning.end() }
    }

    // MARK: - Mode

    private var modePicker: some View {
        Picker("", selection: modeSelection) {
            Text("Now").tag(false)
            Text("Plan a time").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.bottom, planning.isPlanning ? 8 : 10)
    }

    private var modeSelection: Binding<Bool> {
        Binding(
            get: { planning.isPlanning },
            set: { $0 ? planning.begin() : planning.end() }
        )
    }

    // MARK: - Planning header

    private var planningHeader: some View {
        let zone = planning.anchorTimeZone(clocks: store.clocks)
        let proxy = planning.proxyBinding(for: zone)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                DatePicker(
                    "",
                    selection: Binding(get: proxy.get, set: proxy.set),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.field)

                Spacer(minLength: 0)

                Button {
                    planning.begin()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to now")
            }

            Text("Date is in \(anchorName)'s time. Click any time below to type in that zone.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private var anchorName: String {
        guard let id = planning.anchorClockID,
              let clock = store.clocks.first(where: { $0.id == id })
        else { return "your" }
        return clock.label
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        if planning.isPlanning {
            // Your own zone only appears while planning: without it there's nothing
            // anchoring the conversion, but in live mode it would be noise.
            ClockRow(
                label: "You",
                subtitle: Clock.suggestedLabel(for: TimeZone.current.identifier),
                zone: .current,
                instant: displayedInstant,
                use24Hour: store.use24Hour,
                showSeconds: false,
                isAnchor: planning.anchorClockID == nil,
                isPlanning: true,
                onBecomeAnchor: { planning.anchorClockID = nil }
            )
        }

        ForEach(store.clocks) { clock in
            ClockRow(
                label: clock.label,
                subtitle: TimeFormatting.relativeOffsetDescription(displayedInstant, in: clock),
                zone: clock.timeZone,
                instant: displayedInstant,
                use24Hour: store.use24Hour,
                showSeconds: planning.isPlanning ? false : store.showSecondsInPanel,
                isAnchor: planning.isPlanning && planning.anchorClockID == clock.id,
                isPlanning: planning.isPlanning,
                onBecomeAnchor: { planning.anchorClockID = clock.id }
            )
        }
    }

    private var emptyState: some View {
        Text("No clocks yet — add one in Settings.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    // MARK: - Footer

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

// MARK: - Row

private struct ClockRow: View {
    let label: String
    let subtitle: String
    let zone: TimeZone
    let instant: Date
    let use24Hour: Bool
    let showSeconds: Bool
    let isAnchor: Bool
    let isPlanning: Bool
    let onBecomeAnchor: () -> Void

    @ObservedObject private var planning = PlanningState.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if isAnchor {
                let proxy = planning.proxyBinding(for: zone)
                DatePicker(
                    "",
                    selection: Binding(get: proxy.get, set: proxy.set),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: 74)
            } else {
                Text(TimeFormatting.time(
                    instant,
                    in: Clock(label: label, timeZoneID: zone.identifier),
                    use24Hour: use24Hour,
                    showSeconds: showSeconds
                ))
                .font(.system(size: 13))
                .monospacedDigit()
                // Only a hint that it's editable while planning; in live mode the
                // times aren't interactive at all.
                .foregroundStyle(isPlanning ? Color.accentColor : .primary)
                .contentShape(Rectangle())
                .onTapGesture { if isPlanning { onBecomeAnchor() } }
            }

            weekday
        }
        .padding(.vertical, 4)
    }

    private var weekday: some View {
        let clock = Clock(label: label, timeZoneID: zone.identifier)
        return HStack(spacing: 1) {
            Text(TimeFormatting.weekday(instant, in: clock))
            if let badge = TimeFormatting.dayOffsetBadge(instant, in: clock) {
                Text(badge).foregroundStyle(.orange)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        // Reserve the widest case ("Wed+1") so times stay column-aligned
        // whether or not a row carries a day badge.
        .frame(width: 38, alignment: .leading)
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
