import SwiftUI
import WidgetKit

private let focusSnapshotKey = "mobile.widget.groupFocusSnapshot"
private let focusAppGroup = "group.com.example.tkb2622.mobile"

private struct StoredFocusMember: Codable, Hashable {
    let displayName: String
    let avatarID: String
    let startedAt: Date
}

private struct StoredFocusSnapshot: Codable {
    let members: [StoredFocusMember]
    let updatedAt: Date
}

private struct FocusRoomEntry: TimelineEntry {
    let date: Date
    let members: [StoredFocusMember]
    let updatedAt: Date?
    let isLocalPreview: Bool
    let movementPhase: Int
}

private struct FocusRoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusRoomEntry {
        FocusRoomEntry(date: .now, members: [], updatedAt: nil, isLocalPreview: false, movementPhase: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusRoomEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusRoomEntry>) -> Void) {
        let now = Date()
        let isLocalPreview = isLocalPreviewEnabled
        let snapshot = readSnapshot() ?? (isLocalPreview ? localPreviewSnapshot() : nil)
        let entries = FocusRoomTimeline.dates(
            now: now, updatedAt: snapshot?.updatedAt, isLocalPreview: isLocalPreview
        ).map { date in
            FocusRoomEntry(
                date: date,
                members: snapshot?.members ?? [],
                updatedAt: snapshot?.updatedAt,
                isLocalPreview: isLocalPreview,
                movementPhase: FocusRoomTimeline.movementPhase(at: date)
            )
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func makeEntry(at date: Date) -> FocusRoomEntry {
        let isLocalPreview = isLocalPreviewEnabled
        let snapshot = readSnapshot() ?? (isLocalPreview ? localPreviewSnapshot() : nil)
        return FocusRoomEntry(
            date: date,
            members: snapshot?.members ?? [],
            updatedAt: snapshot?.updatedAt,
            isLocalPreview: isLocalPreview,
            movementPhase: FocusRoomTimeline.movementPhase(at: date)
        )
    }

    private var isLocalPreviewEnabled: Bool {
        #if DEBUG
        return UserDefaults(suiteName: focusAppGroup)?.bool(forKey: "mobile.widget.groupFocusLocalPreview") ?? false
        #else
        return false
        #endif
    }

    private func localPreviewSnapshot() -> StoredFocusSnapshot {
        let now = Date()
        return StoredFocusSnapshot(members: [
            StoredFocusMember(displayName: "ちほ", avatarID: "cat", startedAt: now),
            StoredFocusMember(displayName: "ゆう", avatarID: "dragon", startedAt: now),
            StoredFocusMember(displayName: "はる", avatarID: "slime", startedAt: now)
        ], updatedAt: now)
    }

    private func readSnapshot() -> StoredFocusSnapshot? {
        guard let defaults = UserDefaults(suiteName: focusAppGroup),
              let data = defaults.data(forKey: focusSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(StoredFocusSnapshot.self, from: data)
    }
}

private struct FocusRoomWidgetView: View {
    let entry: FocusRoomEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var shouldAnimate: Bool { !reduceMotion && !isLuminanceReduced }

    private var isStale: Bool {
        if entry.isLocalPreview { return false }
        guard let updatedAt = entry.updatedAt else { return true }
        return entry.date.timeIntervalSince(updatedAt) >= FocusRoomTimeline.maximumSnapshotAge
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("集中ルーム")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.30, green: 0.24, blue: 0.18))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.80, green: 0.75, blue: 0.67))

            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.91, blue: 0.81), Color(red: 0.93, green: 0.84, blue: 0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle()
                    .fill(Color(red: 0.79, green: 0.59, blue: 0.41))
                    .frame(height: 26)

                if isStale {
                    Text("アプリを開いて状態を更新")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.36, green: 0.29, blue: 0.23))
                        .padding(.bottom, 45)
                } else if entry.members.isEmpty {
                    Text("いま集中している友達はいません")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.36, green: 0.29, blue: 0.23))
                        .padding(.bottom, 45)
                } else {
                    characterRow
                        .padding(.horizontal, 12)
                        .padding(.bottom, 23)
                        .animation(shouldAnimate ? .easeInOut(duration: 1.4) : nil, value: entry.movementPhase)
                }
            }
            .clipped()
        }
        .containerBackground(Color(red: 0.96, green: 0.90, blue: 0.82), for: .widget)
    }

    private var characterRow: some View {
        let visibleMembers = Array(entry.members.prefix(family == .systemSmall ? 3 : 7))
        return HStack(alignment: .bottom, spacing: family == .systemSmall ? -5 : 2) {
            ForEach(Array(visibleMembers.enumerated()), id: \.offset) { index, member in
                VStack(spacing: 2) {
                    Image(member.avatarID)
                        .resizable()
                        .scaledToFit()
                        .frame(width: characterSize, height: characterSize)
                        .rotationEffect(
                            .degrees(shouldAnimate ? ((index + entry.movementPhase).isMultiple(of: 2) ? -4 : 4) : 0),
                            anchor: .bottom
                        )
                    Text(member.displayName)
                        .font(.system(size: family == .systemSmall ? 8 : 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.32, green: 0.26, blue: 0.20))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .offset(
                    x: shouldAnimate ? movementOffset(for: index) : 0,
                    y: shouldAnimate ? ((index + entry.movementPhase).isMultiple(of: 2) ? -3 : 2) : 0
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if entry.members.count > visibleMembers.count {
                Text("+\(entry.members.count - visibleMembers.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.32, green: 0.26, blue: 0.20))
                    .padding(.bottom, 12)
            }
        }
    }

    private var characterSize: CGFloat { family == .systemSmall ? 38 : 54 }

    private func movementOffset(for index: Int) -> CGFloat {
        let step = (index + entry.movementPhase) % 4
        return CGFloat(step - 1) * (family == .systemSmall ? 2 : 4)
    }
}

@main
struct GroupFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusLinkGroupFocusWidget", provider: FocusRoomProvider()) { entry in
            FocusRoomWidgetView(entry: entry)
        }
        .configurationDisplayName("友達の集中ルーム")
        .description("グループで集中している友達をキャラクターで表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
