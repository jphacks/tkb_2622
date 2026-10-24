import ActivityKit
import Foundation

struct FriendFocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let isFocusing: Bool
        let updatedAt: Date
    }

    let friendName: String
}
