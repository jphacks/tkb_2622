import Foundation

struct SharedFocusSnapshot: Codable, Equatable {
    let friendName: String
    let isFocusing: Bool
    let updatedAt: Date

    static var restingSample: SharedFocusSnapshot {
        SharedFocusSnapshot(friendName: "友だち", isFocusing: false, updatedAt: .now)
    }
}

enum SharedFocusStore {
    static let appGroupID = "group.com.example.tkb2622.friendfocuspoc"
    static let widgetKind = "FriendFocusWidget"
    private static let snapshotKey = "friend-focus.snapshot.v1"

    static func load() -> SharedFocusSnapshot {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(SharedFocusSnapshot.self, from: data)
        else {
            return .restingSample
        }
        return snapshot
    }

    @discardableResult
    static func save(_ snapshot: SharedFocusSnapshot) -> Bool {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = try? JSONEncoder().encode(snapshot)
        else {
            return false
        }
        defaults.set(data, forKey: snapshotKey)
        return true
    }
}
