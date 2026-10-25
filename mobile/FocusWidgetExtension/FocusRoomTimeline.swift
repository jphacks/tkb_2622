import Foundation

enum FocusRoomTimeline {
    static let maximumSnapshotAge: TimeInterval = 12 * 60

    static func dates(now: Date, updatedAt: Date?, isLocalPreview: Bool) -> [Date] {
        guard let updatedAt else { return [now] }
        let expiration = updatedAt.addingTimeInterval(maximumSnapshotAge)
        guard isLocalPreview || expiration > now else { return [now] }

        var dates = (0..<3).map { now.addingTimeInterval(TimeInterval($0 * 5 * 60)) }
        if !isLocalPreview {
            dates = dates.filter { $0 < expiration }
            // Hide old focus status even when iOS postpones the next background fetch.
            dates.append(expiration)
        }
        return dates
    }

    static func movementPhase(at date: Date) -> Int {
        // Keep moving across app-driven reloads instead of restarting every timeline at phase zero.
        Int(date.timeIntervalSince1970 / 60) % 4
    }
}
