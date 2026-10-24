import Combine
import SwiftUI

struct GroupView: View {
  @StateObject private var model = GroupViewModel(repository: ConfiguredGroupRepository())
  @Binding private var invitationToken: String?
  @State private var selectedGroupID: String?
  @State private var isShowingCreateGroup = false
  @State private var newGroupName = ""
  @State private var createOperationID: String?
  @State private var createError: String?
  @State private var isCreatingGroup = false
  @State private var invitationLink: URL?
  @State private var invitationExpiresAt: Date?
  @State private var invitationGroupID: String?
  @State private var invitationOperationID: String?
  @State private var invitationError: String?
  @State private var isCreatingInvitation = false
  @State private var isShowingAcceptInvitation = false
  @State private var acceptError: String?
  @State private var acceptOperationID: String?
  @State private var isAcceptingInvitation = false
  @State private var groupToLeave: MobileGroup?
  @State private var leaveOperationID: String?
  @State private var leaveError: String?
  @State private var groupNotice: String?
  @State private var isLeavingGroup = false
  @State private var isShowingLeaveConfirmation = false
  private let isAuthenticated: Bool
  private let requestSignIn: () -> Void

  init(
    invitationToken: Binding<String?> = .constant(nil),
    isAuthenticated: Bool = true,
    requestSignIn: @escaping () -> Void = {}
  ) {
    _invitationToken = invitationToken
    self.isAuthenticated = isAuthenticated
    self.requestSignIn = requestSignIn
  }

  var body: some View {
    ScreenContainer {
      if isAuthenticated {
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
            Text("グループを作成するか、メンバーから届いた招待リンクで参加できます。")
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

          workStartFeed
        }
      } else {
        SignInRequiredCard(
          title: "グループにはログインが必要です",
          message: "グループや作業開始状況を同期するには、アカウントにログインしてください。",
          onSignIn: requestSignIn
        )
      }
    }
    .refreshable {
      if isAuthenticated {
        await model.load()
        await model.refreshWorkStarts()
      }
    }
    .task(id: isAuthenticated) {
      if isAuthenticated { await model.runWorkStartPolling() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .mobileAuthenticationChanged)) { _ in
      if isAuthenticated {
        Task {
          await model.load()
          await model.refreshWorkStarts()
        }
      }
    }
    .onChange(of: isAuthenticated) { _, authenticated in
      if authenticated {
        showAcceptInvitationIfNeeded()
      }
    }
    .navigationTitle("グループ")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if isAuthenticated {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            isShowingCreateGroup = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("グループを作成")
        }
      }
    }
    .sheet(isPresented: $isShowingCreateGroup, onDismiss: resetCreateGroupForm) {
      createGroupSheet
        .presentationDetents([.medium])
    }
    .onAppear { showAcceptInvitationIfNeeded() }
    .onChange(of: invitationToken) { _, _ in showAcceptInvitationIfNeeded() }
    .confirmationDialog(
      "グループの招待リンク",
      isPresented: $isShowingAcceptInvitation,
      titleVisibility: .visible
    ) {
      Button(isAcceptingInvitation ? "参加中…" : "グループに参加") {
        Task { await acceptInvitation() }
      }
      .disabled(isAcceptingInvitation)
      Button("キャンセル", role: .cancel) { clearInvitationToken() }
    } message: {
      if let acceptError {
        Text(acceptError)
      } else {
        Text("この招待リンクを使ってグループに参加します。招待リンクは1回だけ使用できます。")
      }
    }
    .confirmationDialog(
      "グループから退出しますか？",
      isPresented: $isShowingLeaveConfirmation,
      titleVisibility: .visible
    ) {
      Button("退出する", role: .destructive) {
        Task { await leaveGroup() }
      }
      .disabled(isLeavingGroup)
      Button("キャンセル", role: .cancel) { groupToLeave = nil }
    } message: {
      Text("最後のメンバーが退出するとグループと招待リンクが削除されます。")
    }
    .alert(
      groupNotice == nil ? "グループ操作に失敗しました" : "退出しました",
      isPresented: Binding(
        get: { invitationError != nil || leaveError != nil || groupNotice != nil },
        set: {
          if !$0 {
            invitationError = nil
            leaveError = nil
            groupNotice = nil
          }
        }
      )
    ) {
      Button("閉じる", role: .cancel) {
        invitationError = nil
        leaveError = nil
        groupNotice = nil
      }
    } message: {
      Text(groupNotice ?? invitationError ?? leaveError ?? "もう一度お試しください。")
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
          .disabled(
            newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingGroup)
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
      await model.refreshWorkStarts()
    } catch {
      if let clientError = error as? ConnectJSONClient.ClientError,
        case .connect(code: "invalid_argument") = clientError
      {
        createError = "グループ名は前後の空白を除いて1〜100文字で入力してください。"
      } else {
        createError = GroupAPIErrorMessage.describe(error)
      }
    }
  }

  private func resetCreateGroupForm() {
    newGroupName = ""
    createOperationID = nil
    createError = nil
  }

  private func showAcceptInvitationIfNeeded() {
    guard isAuthenticated, invitationToken != nil else { return }
    isShowingAcceptInvitation = true
  }

  @MainActor
  private func acceptInvitation() async {
    guard let token = invitationToken else { return }
    let operationID = acceptOperationID ?? UUID().uuidString.lowercased()
    acceptOperationID = operationID
    acceptError = nil
    isAcceptingInvitation = true
    defer { isAcceptingInvitation = false }
    do {
      let group = try await model.acceptInvitation(token: token, operationID: operationID)
      selectedGroupID = group.id
      clearInvitationToken()
      await model.refreshWorkStarts()
    } catch {
      acceptError = invitationFailureMessage(error)
      isShowingAcceptInvitation = true
    }
  }

  @MainActor
  private func createInvitation(for groupID: String) async {
    invitationError = nil
    isCreatingInvitation = true
    defer { isCreatingInvitation = false }
    let operationID = invitationOperationID ?? UUID().uuidString.lowercased()
    invitationOperationID = operationID
    do {
      let invitation = try await model.createInvitation(groupID: groupID, operationID: operationID)
      guard let url = GroupInvitationLink.make(token: invitation.token) else {
        invitationError = "招待リンクを作成できませんでした。"
        return
      }
      invitationLink = url
      invitationExpiresAt = invitation.expiresAt.date
      invitationGroupID = groupID
      invitationOperationID = nil
    } catch {
      invitationError = invitationFailureMessage(error)
    }
  }

  @MainActor
  private func leaveGroup() async {
    guard let group = groupToLeave else { return }
    isLeavingGroup = true
    leaveError = nil
    defer { isLeavingGroup = false }
    let operationID = leaveOperationID ?? UUID().uuidString.lowercased()
    leaveOperationID = operationID
    do {
      let deleted = try await model.leaveGroup(groupID: group.id, operationID: operationID)
      selectedGroupID = nil
      invitationLink = nil
      invitationExpiresAt = nil
      invitationGroupID = nil
      invitationOperationID = nil
      leaveOperationID = nil
      groupToLeave = nil
      if deleted {
        groupNotice = "最後のメンバーが退出したため、グループと招待リンクも削除しました。"
      } else {
        groupNotice = "グループから退出しました。"
      }
    } catch {
      leaveError = invitationFailureMessage(error)
    }
  }

  private func clearInvitationToken() {
    invitationToken = nil
    acceptOperationID = nil
    acceptError = nil
    isShowingAcceptInvitation = false
  }

  private func invitationFailureMessage(_ error: Error) -> String {
    if let clientError = error as? ConnectJSONClient.ClientError,
      case .connect(code: "failed_precondition") = clientError
    {
      return "招待リンクは期限切れか、すでに使用されています。新しいリンクを発行してもらってください。"
    }
    return GroupAPIErrorMessage.describe(error)
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
                .overlay(
                  Capsule().stroke(
                    isSelected ? .clear : AppTheme.secondaryInk.opacity(0.25), lineWidth: 1))
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
      let selected = groups.first(where: { $0.id == selectedGroupID })
    {
      return selected
    }
    return groups.first
  }

  private var workStartFeed: some View {
    SurfaceCard {
      Label("作業開始フィード", systemImage: "clock.arrow.circlepath")
        .font(.subheadline.weight(.bold))

      if let workStartError = model.workStartError {
        Text(workStartError)
          .font(.caption)
          .foregroundStyle(.red)
      } else if model.workStarts.isEmpty {
        Text("新しい作業開始はありません。30秒ごとに確認します。")
          .font(.caption)
          .foregroundStyle(AppTheme.secondaryInk)
      } else {
        ForEach(model.workStarts) { event in
          HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
              .foregroundStyle(AppTheme.primary)
            VStack(alignment: .leading, spacing: 3) {
              Text("グループメンバーが作業を開始しました")
                .font(.subheadline.weight(.medium))
              Text(event.startedAt.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
            }
          }
        }
        Text("30秒ごとに確認します。")
          .font(.caption2)
          .foregroundStyle(AppTheme.secondaryInk)
      }
    }
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
          ProfileAvatarImage(avatarID: member.avatarID, size: 40)
          Text(member.displayName)
            .font(.subheadline.weight(.medium))
          if member.isCurrentUser {
            Text("あなた")
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

      Divider()

      Button {
        Task { await createInvitation(for: group.id) }
      } label: {
        Label(
          isCreatingInvitation ? "招待リンクを作成中…" : "招待リンクを作成して共有",
          systemImage: "person.crop.circle.badge.plus"
        )
        .frame(maxWidth: .infinity, minHeight: 42)
      }
      .buttonStyle(.bordered)
      .disabled(isCreatingInvitation || isLeavingGroup)

      if let invitationLink, invitationGroupID == group.id {
        VStack(alignment: .leading, spacing: 8) {
          Text("7日間有効・1回限り")
            .font(.caption.weight(.semibold))
          if let invitationExpiresAt {
            Text("有効期限 \(invitationExpiresAt.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption2)
              .foregroundStyle(AppTheme.secondaryInk)
          }
          ShareLink(item: invitationLink) {
            Label("招待リンクを共有", systemImage: "square.and.arrow.up")
              .frame(maxWidth: .infinity, minHeight: 40)
          }
          .buttonStyle(.borderedProminent)
          .tint(AppTheme.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14))
      }

      if let invitationError {
        Text(invitationError)
          .font(.caption)
          .foregroundStyle(.red)
      }

      if let leaveError {
        Text(leaveError)
          .font(.caption)
          .foregroundStyle(.red)
      }

      Button("このグループから退出", role: .destructive) {
        groupToLeave = group
        isShowingLeaveConfirmation = true
      }
      .frame(maxWidth: .infinity, alignment: .center)
      .disabled(isCreatingInvitation || isLeavingGroup)
    }
  }
}

struct GroupView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack { GroupView() }
  }
}
