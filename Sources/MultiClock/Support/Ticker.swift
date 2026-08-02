import Foundation
import Combine

/// Publishes the current time on a boundary-aligned tick.
///
/// Aligned rather than free-running so the displayed minute flips at :00 instead of
/// drifting up to a second late.
@MainActor
final class Ticker: ObservableObject {
    static let shared = Ticker()

    @Published private(set) var now = Date()

    /// Seconds-resolution consumers (menu bar or panel showing `:ss`) raise this.
    /// Ticking every second when nothing displays seconds just burns wakeups.
    var needsSecondResolution = false {
        didSet { if needsSecondResolution != oldValue { schedule() } }
    }

    private var timer: Timer?

    private init() {
        schedule()
    }

    private func schedule() {
        timer?.invalidate()

        let interval: TimeInterval = needsSecondResolution ? 1 : 60
        let sinceEpoch = Date().timeIntervalSince1970
        let delay = interval - sinceEpoch.truncatingRemainder(dividingBy: interval)

        let timer = Timer(fire: Date().addingTimeInterval(delay), interval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
            }
        }
        // .common so the clock keeps ticking while a menu or panel is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
