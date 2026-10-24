import SwiftUI

private struct SampleGroupPerson: Identifiable {
    let id: String
    let name: String
    let initial: String
    let color: Color
}

struct GroupView: View {
    private let people = [
        SampleGroupPerson(id: "self", name: "あなた", initial: "あ", color: AppTheme.primary),
        SampleGroupPerson(id: "member-1", name: "はると", initial: "は", color: AppTheme.lavender),
        SampleGroupPerson(id: "member-2", name: "みお", initial: "み", color: AppTheme.mint),
        SampleGroupPerson(id: "member-3", name: "そうた", initial: "そ", color: AppTheme.yellow)
    ]

    var body: some View {
        ScreenContainer {
            SampleNotice(title: "グループ画面案・API未接続")

            SurfaceCard {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("研究室")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryInk)
                        Text("JPHACKS チーム")
                            .font(.title3.weight(.bold))
                    }
                    Spacer()
                    Button { } label: {
                        Label("招待", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
            }

            SurfaceCard {
                sectionTitle("最近の作業開始", icon: "bolt.fill")
                activityRow(initial: "は", name: "はると", time: "今日 8:50", color: AppTheme.lavender)
                Divider()
                activityRow(initial: "み", name: "みお", time: "今日 8:32", color: AppTheme.mint)
                Divider()
                activityRow(initial: "そ", name: "そうた", time: "昨日 21:05", color: AppTheme.yellow)
                Text("共有されるのは「作業を始めた」ことだけです。作業記録や残高は共有されません。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            SurfaceCard {
                sectionTitle("メンバー（\(people.count)人）", icon: "person.2")
                ForEach(people) { person in
                    HStack(spacing: 12) {
                        Text(person.initial)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(person.id == "self" ? .white : AppTheme.ink)
                            .frame(width: 38, height: 38)
                            .background(person.color, in: Circle())
                        Text(person.name)
                            .font(.subheadline.weight(.medium))
                        if person.id == "self" {
                            Text("本人")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                }
                Divider()
                Button("このグループから退出") { }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .disabled(true)
            }
        }
        .navigationTitle("グループ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
    }

    private func activityRow(initial: String, name: String, time: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Text(initial)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 36, height: 36)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name)さんが作業を始めました")
                    .font(.subheadline.weight(.medium))
                Text(time)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
    }
}

struct GroupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { GroupView() }
    }
}
