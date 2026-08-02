import Foundation

/// Drives the panel's "what time would that be?" mode.
///
/// Holds a single instant in time. Every row renders that same instant in its own
/// zone, so editing any row is just a different way of naming the same moment.
@MainActor
final class PlanningState: ObservableObject {
    static let shared = PlanningState()

    @Published private(set) var isPlanning = false

    /// The moment being planned. Meaningless unless `isPlanning`.
    @Published var instant = Date()

    /// Which row the typed wall-clock time belongs to. `nil` means the user's own
    /// zone — the default, and the common "I'm free at 9pm" case.
    @Published var anchorClockID: UUID?

    private init() {}

    // MARK: - Mode

    func begin() {
        // Round up to the next quarter hour: these are meeting times, and nobody
        // schedules a call for 21:07.
        let quarter: TimeInterval = 15 * 60
        let now = Date().timeIntervalSince1970
        instant = Date(timeIntervalSince1970: (now / quarter).rounded(.up) * quarter)
        anchorClockID = nil
        isPlanning = true
    }

    func end() {
        isPlanning = false
    }

    // MARK: - Anchor

    func anchorTimeZone(clocks: [Clock]) -> TimeZone {
        guard let id = anchorClockID,
              let clock = clocks.first(where: { $0.id == id })
        else { return .current }
        return clock.timeZone
    }

    // MARK: - Editing

    /// SwiftUI's date and time pickers always interpret their value in the *current*
    /// time zone. To let the user edit a wall clock belonging to another zone, we hand
    /// the picker a shifted "proxy" date whose local reading matches that zone, then
    /// undo the shift on the way back.
    func proxyBinding(for zone: TimeZone) -> (get: () -> Date, set: (Date) -> Void) {
        let offset = { [weak self] (date: Date) -> TimeInterval in
            guard self != nil else { return 0 }
            return TimeInterval(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date))
        }
        return (
            get: { [weak self] in
                guard let self else { return Date() }
                return self.instant.addingTimeInterval(offset(self.instant))
            },
            set: { [weak self] proxy in
                guard let self else { return }
                // Offset is computed from the current instant rather than the proxy so
                // a DST boundary can't make the conversion disagree with itself.
                self.instant = proxy.addingTimeInterval(-offset(self.instant))
            }
        )
    }
}
