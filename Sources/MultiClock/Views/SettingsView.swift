import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ClocksSettingsView()
                .tabItem { Label("Clocks", systemImage: "globe") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 380)
    }
}

// MARK: - Clocks

private struct ClocksSettingsView: View {
    @ObservedObject private var store = ClockStore.shared
    @State private var isPickingTimeZone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Drag to reorder. The order here is the order shown in the dropdown.")
                Text("The clock at the top is the one shown in the menu bar.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($store.clocks) { $clock in
                    HStack(spacing: 10) {
                        TextField("Label", text: $clock.label)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(Clock.suggestedLabel(for: clock.timeZoneID))
                                .font(.system(size: 12))
                            Text(clock.timeZoneID)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if store.primaryClock?.id == clock.id {
                            Text("MENU BAR")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.15))
                                )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { store.moveClocks(from: $0, to: $1) }
                .onDelete { store.removeClocks(at: $0) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Button {
                    isPickingTimeZone = true
                } label: {
                    Label("Add Clock", systemImage: "plus")
                }

                Spacer()

                Text("Select a row and press ⌫ to remove it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .sheet(isPresented: $isPickingTimeZone) {
            TimeZonePicker { identifier in
                store.addClock(timeZoneID: identifier)
                isPickingTimeZone = false
            } onCancel: {
                isPickingTimeZone = false
            }
        }
    }
}

// MARK: - Time zone picker

private struct TimeZonePicker: View {
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var selection: String?

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        guard !query.isEmpty else { return all }
        // Match on the human-facing city too, so "new york" finds America/New_York.
        return all.filter {
            $0.localizedCaseInsensitiveContains(query)
                || Clock.suggestedLabel(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a Clock")
                .font(.headline)

            TextField("Search time zones", text: $query)
                .textFieldStyle(.roundedBorder)

            List(identifiers, id: \.self, selection: $selection) { identifier in
                HStack {
                    Text(Clock.suggestedLabel(for: identifier))
                    Spacer()
                    Text(identifier)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .tag(identifier)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(height: 240)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let selection { onSelect(selection) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @ObservedObject private var store = ClockStore.shared

    var body: some View {
        Form {
            Section {
                // Which clock appears here isn't configurable in this tab: it's the
                // first row on the Clocks tab, changed by dragging.
                LabeledContent("Menu bar clock:") {
                    Text(store.primaryClock.map { clock in
                        clock.label.isEmpty ? clock.timeZoneID : clock.label
                    } ?? "None")
                    .foregroundStyle(.secondary)
                }

                Toggle("Show label next to time", isOn: $store.showLabelInMenuBar)
            }

            Section {
                Toggle("Use 24-hour time", isOn: $store.use24Hour)
                Toggle("Show seconds in menu bar", isOn: $store.showSecondsInMenuBar)
                Toggle("Show seconds in dropdown", isOn: $store.showSecondsInPanel)
            }

            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.showSecondsInMenuBar) { syncTickerResolution() }
        .onChange(of: store.showSecondsInPanel) { syncTickerResolution() }
        .onAppear { syncTickerResolution() }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: { store.launchAtLogin = $0 }
        )
    }

    private func syncTickerResolution() {
        Ticker.shared.needsSecondResolution = store.showSecondsInMenuBar || store.showSecondsInPanel
    }
}
