import Foundation

/// Date formatting for the clock rows.
///
/// `DateFormatter` construction is expensive and these run on every tick for every
/// clock, so formatters are cached by their configuration.
@MainActor
enum TimeFormatting {
    private struct FormatterKey: Hashable {
        let timeZoneID: String
        let template: String
    }

    private static var cache: [FormatterKey: DateFormatter] = [:]

    private static func formatter(timeZoneID: String, template: String) -> DateFormatter {
        let key = FormatterKey(timeZoneID: timeZoneID, template: template)
        if let cached = cache[key] { return cached }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = template
        cache[key] = formatter
        return formatter
    }

    static func time(_ date: Date, in clock: Clock, use24Hour: Bool, showSeconds: Bool) -> String {
        var template = use24Hour ? "HH:mm" : "h:mm"
        if showSeconds { template += ":ss" }
        if !use24Hour { template += " a" }
        return formatter(timeZoneID: clock.timeZoneID, template: template).string(from: date)
    }

    static func weekday(_ date: Date, in clock: Clock) -> String {
        formatter(timeZoneID: clock.timeZoneID, template: "EEE").string(from: date)
    }

    /// Calendar days the clock's zone is ahead of (+) or behind (−) the local zone.
    ///
    /// Compares civil dates, not elapsed time — 23:00 Fri local vs 01:00 Sat remote is
    /// +1 day even though only two hours separate them.
    static func dayOffset(_ date: Date, in clock: Clock) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        var remoteCalendar = Calendar(identifier: .gregorian)
        remoteCalendar.timeZone = clock.timeZone

        let localComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let remoteComponents = remoteCalendar.dateComponents([.year, .month, .day], from: date)

        guard let localDay = calendar.date(from: localComponents),
              let remoteDay = calendar.date(from: remoteComponents) else { return 0 }

        return calendar.dateComponents([.day], from: localDay, to: remoteDay).day ?? 0
    }

    /// "+1" / "−1" / nil when the remote zone is on the same calendar day.
    static func dayOffsetBadge(_ date: Date, in clock: Clock) -> String? {
        let offset = dayOffset(date, in: clock)
        guard offset != 0 else { return nil }
        // U+2212 minus, not a hyphen — lines up with digits.
        return offset > 0 ? "+\(offset)" : "−\(abs(offset))"
    }

    /// Offset from the *user's* zone, which is what matters when coordinating a call.
    static func relativeOffsetDescription(_ date: Date, in clock: Clock) -> String {
        let remote = clock.timeZone.secondsFromGMT(for: date)
        let local = TimeZone.current.secondsFromGMT(for: date)
        let delta = remote - local

        if delta == 0 { return "same as local" }

        let hours = abs(delta) / 3600
        let minutes = (abs(delta) % 3600) / 60
        let magnitude = minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)m"
        return delta > 0 ? "\(magnitude) ahead" : "\(magnitude) behind"
    }
}
