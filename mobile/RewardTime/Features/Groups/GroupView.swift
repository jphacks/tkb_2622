import SwiftUI

struct GroupView: View {
    @StateObject private var model = GroupViewModel(repository: ConfiguredGroupRepository())

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
                ForEach(groups) { group in
                    groupCard(group)
                }

                SurfaceCard {
                    Label("表示できる情報", systemImage: "info.circle")
                        .font(.subheadline.weight(.bold))
                    Text("グループ名と参加メンバーをサーバーから取得しています。メンバー名と作業開始履歴は、対応するAPIがまだないため表示していません。")
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

    private func groupCard(_ group: MobileGroup) -> some View {
        SurfaceCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name)
                        .font(.title3.weight(.bold))
                    Text("メンバー \(group.members.count)人")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
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
