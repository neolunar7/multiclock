import Foundation

/// A single configured clock: a time zone plus the short label shown to the user.
struct Clock: Identifiable, Codable, Hashable {
    var id: UUID
    /// Short label shown in the menu bar and as the row title, e.g. "NY".
    var label: String
    var timeZoneID: String

    init(id: UUID = UUID(), label: String, timeZoneID: String) {
        self.id = id
        self.label = label
        self.timeZoneID = timeZoneID
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .gmt
    }

    /// "America/New_York" -> "New York". Used when the user hasn't set a label yet.
    static func suggestedLabel(for timeZoneID: String) -> String {
        let city = timeZoneID.split(separator: "/").last.map(String.init) ?? timeZoneID
        return city.replacingOccurrences(of: "_", with: " ")
    }
}
