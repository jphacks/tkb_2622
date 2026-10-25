import Combine
import Foundation
import UIKit
import WidgetKit

struct GroupFocusWidgetSnapshot: Codable, Equatable {
    let members: [MobileGroupFocusMember]
    let updatedAt: Date
}

enum GroupFocusWidgetCache {
    static let widgetKind = "FocusLinkGroupFocusWidget"
    private static let key = "mobile.widget.groupFocusSnapshot"

    static func read() -> GroupFocusWidgetSnapshot? {
        guard let data = ScreenTimeSharedStorage.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GroupFocusWidgetSnapshot.self, from: data)
    }

    static func save(members: [MobileGroupFocusMember], updatedAt: Date = Date()) {
        let snapshot = GroupFocusWidgetSnapshot(members: members, updatedAt: updatedAt)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        ScreenTimeSharedStorage.defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func clear() {
        ScreenTimeSharedStorage.defaults.removeObject(forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

@MainActor
final class GroupFocusWidgetSyncCoordinator: ObservableObject {
    func run(isAuthenticated: Bool) async {
        guard isAuthenticated else {
            GroupFocusWidgetCache.clear()
            return
        }

        while !Task.isCancelled {
            if UIApplication.shared.applicationState == .active {
                do {
                    let members = try await ConfiguredGroupRepository().fetchFocusedMembers()
                    GroupFocusWidgetCache.save(members: members)
                } catch {
                    // Keep the last successful snapshot; the widget marks old data as stale.
                }
            }

            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                return
            }
        }
    }
}
