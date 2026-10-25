import Combine
import Foundation
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
    static let shared = GroupFocusWidgetSyncCoordinator()

    private let fetchMembers: () async throws -> [MobileGroupFocusMember]
    private let currentUserID: @MainActor () -> String?
    private let save: ([MobileGroupFocusMember]) -> Void
    private let clear: () -> Void
    private let isShowingLocalPreview: () -> Bool
    private var requestGeneration = 0

    init(
        fetchMembers: @escaping () async throws -> [MobileGroupFocusMember] = {
            try await ConfiguredGroupRepository().fetchFocusedMembers()
        },
        currentUserID: @escaping @MainActor () -> String? = {
            guard !UserDefaults.standard.bool(forKey: "mobile.auth.loginDeferred") else { return nil }
            return MobileAppConfiguration.makeAuthService()?.authenticatedUserID
        },
        save: @escaping ([MobileGroupFocusMember]) -> Void = { GroupFocusWidgetCache.save(members: $0) },
        clear: @escaping () -> Void = { GroupFocusWidgetCache.clear() },
        isShowingLocalPreview: @escaping () -> Bool = {
            #if DEBUG
            return GroupFocusWidgetCache.isShowingLocalPreview
            #else
            return false
            #endif
        }
    ) {
        self.fetchMembers = fetchMembers
        self.currentUserID = currentUserID
        self.save = save
        self.clear = clear
        self.isShowingLocalPreview = isShowingLocalPreview
    }

    func run(isAuthenticated: Bool, isActive: Bool) async {
        guard isAuthenticated else {
            clear()
            return
        }
        guard isActive else { return }

        while !Task.isCancelled {
            await synchronize()

            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                return
            }
        }
    }

    @discardableResult
    func synchronize() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard !isShowingLocalPreview() else { return true }
        guard let userID = currentUserID() else {
            clear()
            return false
        }
        requestGeneration += 1
        let generation = requestGeneration

        do {
            let members = try await fetchMembers()
            try Task.checkCancellation()
            // Discard responses from a previous account or a request cancelled on scene changes.
            guard generation == requestGeneration,
                  currentUserID() == userID, !isShowingLocalPreview() else { return false }
            save(members)
            return true
        } catch {
            // Keep the last successful snapshot; the widget marks old data as stale.
            return false
        }
    }
}
