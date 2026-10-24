import SwiftUI

struct GroupView: View {
    @StateObject private var model = GroupViewModel(repository: ConfiguredGroupRepository())
    @State private var selectedGroupID: String?
    @State private var isShowingCreateGroup = false
    @State private var newGroupName = ""
    @State private var createOperationID: String?
    @State private var createError: String?
    @State private var isCreatingGroup = false

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
                    Text("グループを作成するとここに表示されます。招待からの参加は未対応です。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Button("グループを作成") {
                        isShowingCreateGroup = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingCreateGroup = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("グループを作成")
            }
        }
        .sheet(isPresented: $isShowingCreateGroup, onDismiss: resetCreateGroupForm) {
            createGroupSheet
                .presentationDetents([.medium])
        }
    }

    private var createGroupSheet: some View {
        NavigationStack {
            Form {
                Section("グループ名") {
                    TextField("例：研究室", text: $newGroupName)
                        .textInputAutocapitalization(.never)
                        .onChange(of: newGroupName) { _, _ in
                            createOperationID = nil
                            createError = nil
                        }
                    Text("前後の空白を除いて1〜100文字")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }

                if let createError {
                    Section {
                        Text(createError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("グループを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isShowingCreateGroup = false }
                        .disabled(isCreatingGroup)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submitCreateGroup() }
                    } label: {
                        if isCreatingGroup {
                            ProgressView()
                        } else {
                            Text("作成")
                        }
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingGroup)
                }
            }
        }
    }

    @MainActor
    private func submitCreateGroup() async {
        let operationID = createOperationID ?? UUID().uuidString.lowercased()
        createOperationID = operationID
        isCreatingGroup = true
        defer { isCreatingGroup = false }

        do {
            let group = try await model.createGroup(name: newGroupName, operationID: operationID)
            selectedGroupID = group.id
            isShowingCreateGroup = false
        } catch {
            if let clientError = error as? ConnectJSONClient.ClientError,
               case .connect(code: "invalid_argument") = clientError {
                createError = "グループ名は前後の空白を除いて1〜100文字で入力してください。"
            } else {
                createError = (error as? LocalizedError)?.errorDescription
                    ?? "グループを作成できませんでした。接続状態を確認して再試行してください。"
            }
        }
    }

    private func resetCreateGroupForm() {
        newGroupName = ""
        createOperationID = nil
        createError = nil
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
