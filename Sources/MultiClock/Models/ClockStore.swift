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

    /// Order is meaningful: the first clock is the one shown in the menu bar.
    @Published var clocks: [Clock] { didSet { save() } }
    @Published var use24Hour: Bool { didSet { save() } }
    @Published var showSecondsInMenuBar: Bool { didSet { save() } }
    @Published var showSecondsInPanel: Bool { didSet { save() } }
    @Published var showLabelInMenuBar: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard
    private var isLoading = false

    private enum Key {
        static let clocks = "clocks"
        /// Only read once, to migrate installs from when the menu bar clock was
        /// picked explicitly rather than derived from order.
        static let legacyPrimary = "primaryClockID"
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

        use24Hour = defaults.object(forKey: Key.use24Hour) as? Bool ?? true
        showSecondsInMenuBar = defaults.object(forKey: Key.secondsMenuBar) as? Bool ?? false
        showSecondsInPanel = defaults.object(forKey: Key.secondsPanel) as? Bool ?? false
        showLabelInMenuBar = defaults.object(forKey: Key.labelInMenuBar) as? Bool ?? true

        migrateLegacyPrimaryClock()

        isLoading = false
    }

    /// The menu bar clock used to be chosen with a picker; it's now whichever clock
    /// sorts first. Promote the previously-picked clock so an upgrade doesn't
    /// silently swap what someone sees in their menu bar.
    private func migrateLegacyPrimaryClock() {
        defer { defaults.removeObject(forKey: Key.legacyPrimary) }

        guard let stored = defaults.string(forKey: Key.legacyPrimary),
              let id = UUID(uuidString: stored),
              let index = clocks.firstIndex(where: { $0.id == id }),
              index != 0
        else { return }

        let promoted = clocks.remove(at: index)
        clocks.insert(promoted, at: 0)
        save(force: true)
    }

    /// Seeded so a fresh install shows something meaningful instead of an empty menu bar.
    private static func defaultClocks() -> [Clock] {
        [
            Clock(label: "NY", timeZoneID: "America/New_York"),
            Clock(label: "SF", timeZoneID: "America/Los_Angeles"),
        ]
    }

    /// The clock shown in the menu bar: always the first, so dragging a row to the
    /// top is how you change it.
    var primaryClock: Clock? {
        clocks.first
    }

    // MARK: - Mutation

    func addClock(timeZoneID: String) {
        let clock = Clock(label: Clock.suggestedLabel(for: timeZoneID), timeZoneID: timeZoneID)
        // Appended, not inserted: adding a clock shouldn't hijack the menu bar.
        clocks.append(clock)
    }

    func removeClocks(at offsets: IndexSet) {
        clocks.remove(atOffsets: offsets)
    }

    func moveClocks(from source: IndexSet, to destination: Int) {
        clocks.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    /// `force` is for writes during init, where `isLoading` is still suppressing the
    /// `didSet` saves (the migration needs its reorder persisted).
    private func save(force: Bool = false) {
        guard force || !isLoading else { return }
        if let data = try? JSONEncoder().encode(clocks) {
            defaults.set(data, forKey: Key.clocks)
        }
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
