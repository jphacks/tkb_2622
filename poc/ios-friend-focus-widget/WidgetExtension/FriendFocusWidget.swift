import SwiftUI
import WidgetKit

struct FriendFocusEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedFocusSnapshot
}

struct FriendFocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FriendFocusEntry {
        FriendFocusEntry(date: .now, snapshot: .restingSample)
    }

    func getSnapshot(in context: Context, completion: @escaping (FriendFocusEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FriendFocusEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> FriendFocusEntry {
        FriendFocusEntry(date: .now, snapshot: SharedFocusStore.load())
    }
}

struct FriendFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedFocusStore.widgetKind, provider: FriendFocusProvider()) { entry in
            FriendFocusWidgetView(entry: entry)
        }
        .configurationDisplayName("友だちの集中")
        .description("友だちが集中しているとき、キャラクターが作業中の姿になります。")
        .supportedFamilies([.systemSmall])
    }
}

struct FriendFocusWidgetView: View {
    let entry: FriendFocusEntry

    private var actionCharacter: String {
        entry.snapshot.isFocusing ? "🐱‍💻" : "🐱☕️"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.snapshot.isFocusing ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                Text("\(entry.snapshot.friendName)の状態")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.isFocusing ? "集中中" : "休憩中")
                        .font(.headline)
                    Text(entry.snapshot.updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(actionCharacter)
                    .font(.system(size: 38))
                    .id(entry.snapshot.isFocusing)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.6), value: entry.snapshot.isFocusing)
                    .accessibilityLabel(entry.snapshot.isFocusing ? "猫のキャラクターが作業中" : "猫のキャラクターが休憩中")
            }
        }
        .padding(16)
        .containerBackground(Color(red: 0.95, green: 0.94, blue: 1.0), for: .widget)
    }
}

@main
struct FriendFocusWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendFocusWidget()
        FriendFocusLiveActivityWidget()
    }
}

struct FriendFocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FriendFocusActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Text(context.state.isFocusing ? "🐱‍💻" : "🐱☕️")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.isFocusing ? "\(context.attributes.friendName)が集中中" : "\(context.attributes.friendName)は休憩中")
                        .font(.headline)
                    Text("更新: \(context.state.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.95, green: 0.94, blue: 1.0))
            .activitySystemActionForegroundColor(.purple)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.isFocusing ? "🐱‍💻" : "🐱☕️")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isFocusing ? "集中中" : "休憩中")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.friendName) · \(context.state.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                }
            } compactLeading: {
                Text("🐱")
            } compactTrailing: {
                Text(context.state.isFocusing ? "集中" : "休憩")
            } minimal: {
                Text("🐱")
            }
            .keylineTint(.purple)
        }
    }
}
