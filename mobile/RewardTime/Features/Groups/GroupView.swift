import SwiftUI

struct GroupView: View {
    @StateObject private var model = GroupViewModel(repository: ConfiguredGroupRepository())
    @State private var selectedGroupID: String?

    var body: some View {
        ScreenContainer {
            switch model.state {
            case .loading:
                SurfaceCard {
                    ProgressView("グループを読み込み中…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .failed(let message):
                SurfaceCard {
                    Label("グループを読み込めませんでした", systemImage: "wifi.exclamationmark")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Button("再読み込み") {
                        Task { await model.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                }
            case .loaded(let groups) where groups.isEmpty:
                SurfaceCard {
                    Label("所属グループはありません", systemImage: "person.2")
                        .font(.headline)
                    Text("グループへの参加後、ここに一覧が表示されます。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            case .loaded(let groups):
                groupPicker(groups)

                if let group = selectedGroup(in: groups) {
                    groupCard(group)
                }

                SurfaceCard {
                    Label("未対応のグループ機能", systemImage: "info.circle")
                        .font(.subheadline.weight(.bold))
                    Text("作業開始フィード、メンバーの表示名、招待、退出はbackend APIが未対応です。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .navigationTitle("グループ")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func groupPicker(_ groups: [MobileGroup]) -> some View {
        if groups.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups) { group in
                        let isSelected = selectedGroup(in: groups)?.id == group.id
                        Button {
                            selectedGroupID = group.id
                        } label: {
                            Text(group.name)
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .white : AppTheme.ink)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 38)
                                .background(isSelected ? AppTheme.ink : .white, in: Capsule())
                                .overlay(Capsule().stroke(isSelected ? .clear : AppTheme.secondaryInk.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func selectedGroup(in groups: [MobileGroup]) -> MobileGroup? {
        if let selectedGroupID,
           let selected = groups.first(where: { $0.id == selectedGroupID }) {
            return selected
        }
        return groups.first
    }

    private func groupCard(_ group: MobileGroup) -> some View {
        SurfaceCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name)
                        .font(.title3.weight(.bold))
                    Text("メンバー \(group.members.count)人")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                    if let createdAt = group.createdAt?.date {
                        Text("作成 \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                Spacer()
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AppTheme.primary)
                    .padding(10)
                    .background(AppTheme.lavender, in: Circle())
            }

            Divider()

            ForEach(Array(group.members.enumerated()), id: \.offset) { _, member in
                HStack(spacing: 11) {
                    Image(systemName: member.isCurrentUser ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(member.isCurrentUser ? AppTheme.primary : AppTheme.secondaryInk)
                    Text(member.isCurrentUser ? "あなた" : "メンバー")
                        .font(.subheadline.weight(.medium))
                    if member.isCurrentUser {
                        Text("本人")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    Spacer()
                    if let joinedAt = member.joinedAt?.date {
                        Text("参加 \(joinedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
            }
        }
    }
}

struct GroupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { GroupView() }
    }
}
