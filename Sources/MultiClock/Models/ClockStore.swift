import Foundation
import ServiceManagement

/// Owns the user's clocks and display preferences, persisted to `UserDefaults`.
///
/// Accessed through `ClockStore.shared` rather than the SwiftUI environment: the
/// `MenuBarExtra` label renders in its own hosting context, where environment
/// objects injected at the `Scene` level don't reliably reach it.
@MainActor
final class ClockStore: ObservableObject {
    static let shared = ClockStore()

    @Published var clocks: [Clock] { didSet { save() } }
    /// Which clock is rendered in the menu bar itself. Falls back to the first clock.
    @Published var primaryClockID: UUID? { didSet { save() } }
    @Published var use24Hour: Bool { didSet { save() } }
    @Published var showSecondsInMenuBar: Bool { didSet { save() } }
    @Published var showSecondsInPanel: Bool { didSet { save() } }
    @Published var showLabelInMenuBar: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard
    private var isLoading = false

    private enum Key {
        static let clocks = "clocks"
        static let primary = "primaryClockID"
        static let use24Hour = "use24Hour"
        static let secondsMenuBar = "showSecondsInMenuBar"
        static let secondsPanel = "showSecondsInPanel"
        static let labelInMenuBar = "showLabelInMenuBar"
    }

    private init() {
        isLoading = true

        let stored = defaults.data(forKey: Key.clocks)
            .flatMap { try? JSONDecoder().decode([Clock].self, from: $0) }
        clocks = stored ?? Self.defaultClocks()

        primaryClockID = defaults.string(forKey: Key.primary).flatMap(UUID.init(uuidString:))
        use24Hour = defaults.object(forKey: Key.use24Hour) as? Bool ?? true
        showSecondsInMenuBar = defaults.object(forKey: Key.secondsMenuBar) as? Bool ?? false
        showSecondsInPanel = defaults.object(forKey: Key.secondsPanel) as? Bool ?? false
        showLabelInMenuBar = defaults.object(forKey: Key.labelInMenuBar) as? Bool ?? true

        isLoading = false

        // A stale primary (clock deleted in a previous run) would blank the menu bar.
        if let id = primaryClockID, !clocks.contains(where: { $0.id == id }) {
            primaryClockID = clocks.first?.id
        }
    }

    /// Seeded so a fresh install shows something meaningful instead of an empty menu bar.
    private static func defaultClocks() -> [Clock] {
        [
            Clock(label: "NY", timeZoneID: "America/New_York"),
            Clock(label: "SF", timeZoneID: "America/Los_Angeles"),
        ]
    }

    var primaryClock: Clock? {
        if let id = primaryClockID, let match = clocks.first(where: { $0.id == id }) {
            return match
        }
        return clocks.first
    }

    // MARK: - Mutation

    func addClock(timeZoneID: String) {
        let clock = Clock(label: Clock.suggestedLabel(for: timeZoneID), timeZoneID: timeZoneID)
        clocks.append(clock)
        if primaryClockID == nil { primaryClockID = clock.id }
    }

    func removeClocks(at offsets: IndexSet) {
        let removed = offsets.map { clocks[$0].id }
        clocks.remove(atOffsets: offsets)
        if let id = primaryClockID, removed.contains(id) {
            primaryClockID = clocks.first?.id
        }
    }

    func moveClocks(from source: IndexSet, to destination: Int) {
        clocks.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    private func save() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(clocks) {
            defaults.set(data, forKey: Key.clocks)
        }
        defaults.set(primaryClockID?.uuidString, forKey: Key.primary)
        defaults.set(use24Hour, forKey: Key.use24Hour)
        defaults.set(showSecondsInMenuBar, forKey: Key.secondsMenuBar)
        defaults.set(showSecondsInPanel, forKey: Key.secondsPanel)
        defaults.set(showLabelInMenuBar, forKey: Key.labelInMenuBar)
    }

    // MARK: - Launch at login

    /// Reads through to the system rather than caching: the user can revoke this in
    /// System Settings at any time, and a cached value would silently disagree.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("MultiClock: launch-at-login toggle failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
