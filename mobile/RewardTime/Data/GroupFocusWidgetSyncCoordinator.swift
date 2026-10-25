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
    #if DEBUG
    private static let localPreviewKey = "mobile.widget.groupFocusLocalPreview"
    #endif

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
        #if DEBUG
        ScreenTimeSharedStorage.defaults.removeObject(forKey: localPreviewKey)
        #endif
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    #if DEBUG
    static var isShowingLocalPreview: Bool {
        ScreenTimeSharedStorage.defaults.bool(forKey: localPreviewKey)
    }

    static func showLocalPreview() {
        let now = Date()
        let members = [
            MobileGroupFocusMember(displayName: "ちほ", avatarID: "cat", startedAt: now),
            MobileGroupFocusMember(displayName: "ゆう", avatarID: "dragon", startedAt: now),
            MobileGroupFocusMember(displayName: "はる", avatarID: "slime", startedAt: now)
        ]
        ScreenTimeSharedStorage.defaults.set(true, forKey: localPreviewKey)
        save(members: members, updatedAt: now)
    }

    static func hideLocalPreview() {
        ScreenTimeSharedStorage.defaults.removeObject(forKey: localPreviewKey)
        clear()
    }
    #endif
}

@MainActor
final class GroupFocusWidgetSyncCoordinator: ObservableObject {
    func run(isAuthenticated: Bool) async {
        guard isAuthenticated else {
            GroupFocusWidgetCache.clear()
            return
        }

        while !Task.isCancelled {
            #if DEBUG
            let isShowingLocalPreview = GroupFocusWidgetCache.isShowingLocalPreview
            #else
            let isShowingLocalPreview = false
            #endif
            if !isShowingLocalPreview && UIApplication.shared.applicationState == .active {
                do {
                    let members = try await ConfiguredGroupRepository().fetchFocusedMembers()
                    #if DEBUG
                    // A request may have started just before local preview was enabled.
                    if !GroupFocusWidgetCache.isShowingLocalPreview {
                        GroupFocusWidgetCache.save(members: members)
                    }
                    #else
                    GroupFocusWidgetCache.save(members: members)
                    #endif
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
