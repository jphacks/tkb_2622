import Combine
import SwiftUI

struct HomeView: View {
  private static let synchronizationIntervalNanoseconds: UInt64 = 30_000_000_000

  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var viewModel: HomeViewModel
  @ObservedObject private var screenTime: MobileScreenTimeController
  private let isAuthenticated: Bool
  private let isVisible: Bool
  private let requestSignIn: () -> Void
  private let apiSyncError: String?
  private let retryAPISync: () async -> Void

  init(
    repository: any HomeRepository = ConfiguredHomeRepository(),
    screenTime: MobileScreenTimeController,
    isAuthenticated: Bool = true,
    isVisible: Bool = true,
    requestSignIn: @escaping () -> Void = {},
    apiSyncError: String? = nil,
    retryAPISync: @escaping () async -> Void = {}
  ) {
    _viewModel = StateObject(wrappedValue: HomeViewModel(repository: repository))
    _screenTime = ObservedObject(wrappedValue: screenTime)
    self.isAuthenticated = isAuthenticated
    self.isVisible = isVisible
    self.requestSignIn = requestSignIn
    self.apiSyncError = apiSyncError
    self.retryAPISync = retryAPISync
  }

  var body: some View {
    ScreenContainer {
      if isAuthenticated {
        if let apiSyncError {
          apiSyncWarning(apiSyncError)
        }
        switch viewModel.state {
        case .loading:
          ProgressView("状態を読み込み中…")
            .frame(maxWidth: .infinity, minHeight: 180)
        case .loaded(let snapshot):
          if let refreshError = viewModel.refreshError {
            refreshWarning(refreshError)
          }
          sessionCard(snapshot)
          rewardBalanceCard(snapshot)
          restrictedAppsCard(snapshot)
          restrictionStateCard(snapshot)
          breakAction(snapshot)
        case .failed(let message):
          errorCard(message: message)
        }
      } else {
        SignInRequiredCard(
          title: "ログインすると作業状態を同期できます",
          message: "作業時間や報酬残高を表示するには、アカウント接続が必要です。",
          onSignIn: requestSignIn
        )
      }

    }
    .navigationTitle("Focus Link")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: shouldSynchronize) {
      guard shouldSynchronize else { return }
      await refreshAndReconcile()

      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: Self.synchronizationIntervalNanoseconds)
        } catch {
          return
        }
        guard shouldSynchronize else { return }
        await refreshAndReconcile()
      }
    }
    .refreshable {
      if isAuthenticated { await loadAndReconcile() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .mobileAuthenticationChanged)) { _ in
      if shouldSynchronize { Task { await refreshAndReconcile() } }
    }
  }

  private var shouldSynchronize: Bool {
    isAuthenticated && isVisible && scenePhase == .active
  }

  @MainActor
  private func loadAndReconcile() async {
    let refreshed = await viewModel.refresh()
    guard refreshed else { return }
    await reconcileLoadedSnapshot()
  }

  @MainActor
  private func refreshAndReconcile() async {
    let refreshed = await viewModel.refresh()
    guard !Task.isCancelled else { return }
    guard refreshed else { return }
    await reconcileLoadedSnapshot()
  }

  @MainActor
  private func reconcileLoadedSnapshot() async {
    guard case .loaded(let snapshot) = viewModel.state else { return }
    await screenTime.reconcileServerRestriction(snapshot)
  }

  private func sessionCard(_ snapshot: MobileHomeSnapshot) -> some View {
    SurfaceCard(padding: 20) {
      HStack(spacing: 8) {
        Circle()
          .fill(snapshot.sessionStatus == .working ? AppTheme.primary : AppTheme.teal)
          .frame(width: 10, height: 10)
        Text(sessionTitle(snapshot.sessionStatus))
          .font(.subheadline.weight(.bold))
          .foregroundStyle(AppTheme.primary)
      }

      VStack(alignment: .leading, spacing: 5) {
        Text("計測時間")
          .font(.caption.weight(.medium))
          .foregroundStyle(AppTheme.secondaryInk)
        Text(formattedWorkTime(snapshot.elapsedMinutes))
          .font(.system(size: 48, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(AppTheme.ink)
          .accessibilityIdentifier("elapsedWorkTime")
      }

      if snapshot.elapsedMinutes != nil,
        let minimumSeconds = snapshot.minimumSeconds
      {
        let progress = snapshot.minimumProgress ?? 0
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(AppTheme.lavender)
            Capsule().fill(AppTheme.primary).frame(width: geometry.size.width * progress)
          }
        }
        .frame(height: 8)
        Text(
          snapshot.minimumReached
            ? "最小作業時間を達成"
            : "最小作業時間 \(formattedDuration(minimumSeconds)) まで計測中"
        )
        .font(.footnote.weight(.medium))
        .foregroundStyle(AppTheme.secondaryInk)
      } else {
        Text(sessionDescription(snapshot.sessionStatus))
          .font(.footnote)
          .foregroundStyle(AppTheme.secondaryInk)
      }
    }
  }

  private func refreshWarning(_ message: String) -> some View {
    SurfaceCard {
      Label("最新の状態を取得できませんでした", systemImage: "wifi.exclamationmark")
        .font(.subheadline.weight(.semibold))
      Text("前回取得した内容を表示しています。通信が回復したら再読み込みしてください。")
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryInk)
      Text(message)
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryInk)
      Button("再試行") { Task { await refreshAndReconcile() } }
        .buttonStyle(.bordered)
    }
  }

  private func apiSyncWarning(_ message: String) -> some View {
    SurfaceCard {
      Label("サーバー同期に失敗しました", systemImage: "exclamationmark.triangle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.red)
      Text("詳細を確認し、通信が戻ったら再試行してください。")
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryInk)
      Text(message)
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryInk)
      Button("同期を再試行") {
        Task { await retryAPISync() }
      }
      .buttonStyle(.bordered)
    }
  }

  private func rewardBalanceCard(_ snapshot: MobileHomeSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 5) {
          Text("報酬の残高")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(snapshot.rewardBalanceMinutes.formatted())
              .font(.system(size: 34, weight: .bold, design: .rounded))
              .monospacedDigit()
              .accessibilityIdentifier("rewardBalanceMinutes")
            Text("分")
              .font(.title3.weight(.semibold))
          }
          .foregroundStyle(.white)
        }
        Spacer(minLength: 8)
        Image(systemName: "hourglass")
          .font(.title2)
          .foregroundStyle(.white)
          .padding(14)
          .background(.white.opacity(0.15), in: Circle())
      }

      Text("今回の報酬は作業セッション中の小休憩に使えます。終了・中止時に未使用分は破棄されます。")
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.88))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 20))
  }

  private func restrictedAppsCard(_ snapshot: MobileHomeSnapshot) -> some View {
    let hasLocalSelection = screenTime.hasSelectionBeenConfigured || !snapshot.isSampleData
    let selectedTokens = Array(screenTime.restrictedApplicationTokens)
    let count =
      hasLocalSelection
      ? screenTime.restrictedApplicationCount
      : (snapshot.restrictedApplicationCount ?? snapshot.restrictedApps.count)

    return SurfaceCard {
      HStack {
        Text("制限するアプリ")
          .font(.subheadline.weight(.bold))
        Spacer()
        Text("\(count)個")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.primary)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(AppTheme.lavender, in: Capsule())
      }

      if hasLocalSelection && !selectedTokens.isEmpty {
        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
          alignment: .leading, spacing: 8
        ) {
          ForEach(selectedTokens, id: \.self) { token in
            Label(token)
              .font(.caption.weight(.medium))
              .labelStyle(.titleAndIcon)
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
          }
        }
      } else if !hasLocalSelection && !snapshot.restrictedApps.isEmpty {
        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
          alignment: .leading, spacing: 8
        ) {
          ForEach(snapshot.restrictedApps, id: \.self) { app in
            Label(app, systemImage: "app.fill")
              .font(.caption.weight(.medium))
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
          }
        }
      } else if count > 0 {
        Text("選択したアプリを表示できません。設定から選び直してください。")
          .font(.footnote)
          .foregroundStyle(AppTheme.secondaryInk)
      } else {
        Text(
          !screenTime.isAuthorized
            ? "スクリーンタイムを許可すると、設定から対象アプリを選べます。"
            : "設定から制限するアプリを選べます。"
        )
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryInk)
      }

      Label(
        screenTime.appliedRestrictionLabel,
        systemImage: screenTime.hasAppliedRestriction ? "checkmark.shield.fill" : "lock.open"
      )
      .font(.footnote.weight(.semibold))
      .foregroundStyle(
        screenTime.hasAppliedRestriction ? AppTheme.teal : AppTheme.secondaryInk)

      Text("選択したアプリはMacで作業中に自動で制限されます。報酬の利用枠を確保すると一時解除されます。")
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryInk)
    }
  }

  private func restrictionStateCard(_ snapshot: MobileHomeSnapshot) -> some View {
    SurfaceCard {
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 10) {
          Text("サーバーの要求：\(desiredRestrictionLabel(snapshot.desiredRestriction))")
            .font(.footnote.weight(.medium))

          Label("iPhoneでの適用状態", systemImage: "lock.iphone")
            .font(.subheadline.weight(.bold))

          switch snapshot.restrictionStatus {
          case .unrestricted:
            Text("制限解除済み").foregroundStyle(AppTheme.secondaryInk)
          case .restricted:
            Text("制限中").foregroundStyle(AppTheme.teal)
          case .temporarilyReleased(let endsAt):
            if let endsAt {
              Text("一時解除中・終了予定 \(endsAt.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(AppTheme.teal)
            } else {
              Text("一時解除中").foregroundStyle(AppTheme.teal)
            }
          case .notConfirmed:
            Text("iPhoneでの適用を確認できていません").foregroundStyle(AppTheme.secondaryInk)
          case .failed:
            Text("iPhoneでの適用に失敗しました。設定を確認してください。").foregroundStyle(.red)
          }

          Text("サーバーの要求とiPhoneから報告された適用状態を分けて表示します。")
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryInk)
        }
        .padding(.top, 10)
      } label: {
        Label("同期と制限の詳細", systemImage: "server.rack")
          .font(.subheadline.weight(.bold))
      }
      .tint(AppTheme.primary)
    }
  }

  private func desiredRestrictionLabel(_ mode: DesiredRestrictionMode) -> String {
    switch mode {
    case .unrestricted: "制限解除を要求"
    case .shielded: "制限を要求"
    case .timedUnlock: "利用枠の間、一時解除を要求"
    case .sessionEnded: "作業終了後の制限解除を要求"
    case .unknown: "サーバーの要求状態を確認できません"
    }
  }

  @ViewBuilder
  private func breakAction(_ snapshot: MobileHomeSnapshot) -> some View {
    if snapshot.sessionStatus == .paused {
      if let grantID = snapshot.activeGrantID,
        let reservedSeconds = snapshot.activeGrantReservedSeconds,
        ["GRANT_STATUS_RESERVED", "GRANT_STATUS_ACTIVATED"].contains(
          snapshot.activeGrantStatus ?? "")
      {
        NavigationLink {
          ActiveUsageView(grantID: grantID, reservedSeconds: Int64(reservedSeconds))
        } label: {
          Label("利用中の枠を確認", systemImage: "timer")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.primary)
      } else {
        NavigationLink {
          UsageReservationView(
            balanceMinutes: snapshot.rewardBalanceMinutes,
            sessionID: snapshot.sessionID ?? "",
            sessionVersion: snapshot.sessionVersion ?? 0,
            screenTime: screenTime
          )
        } label: {
          Label("残高を使う", systemImage: "cup.and.saucer.fill")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.primary)
        .disabled(snapshot.rewardBalanceMinutes <= 0)
      }
    } else {
      Label {
        Text(
          snapshot.sessionStatus == .working
            ? "残高を使うには、Macで作業を一時停止してください。"
            : "作業セッション中の小休憩で残高を使えます。")
      } icon: {
        Image(systemName: "info.circle")
      }
      .font(.footnote)
      .foregroundStyle(AppTheme.secondaryInk)
      .padding(.horizontal, 2)
    }
  }

  private func errorCard(message: String) -> some View {
    SurfaceCard {
      Label("状態を読み込めませんでした", systemImage: "wifi.exclamationmark")
        .font(.headline)
      Text(message)
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryInk)
      Button("再読み込み") {
        Task { await viewModel.load() }
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.primary)
    }
  }

  private func formattedWorkTime(_ minutes: Int?) -> String {
    guard let minutes else { return "--:--" }
    return String(format: "%d:%02d", minutes / 60, minutes % 60)
  }

  private func formattedDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    return remainder == 0 ? "\(minutes)分" : "\(minutes)分\(remainder)秒"
  }

  private func sessionTitle(_ status: SessionStatus) -> String {
    switch status {
    case .noSession: "作業セッションなし"
    case .working: "Mac で作業中"
    case .paused: "Mac で一時停止中"
    }
  }

  private func sessionDescription(_ status: SessionStatus) -> String {
    switch status {
    case .noSession: "作業を始めると、ここに状態が表示されます。"
    case .working: "作業の記録はMacから同期されます。"
    case .paused: "小休憩の利用枠を確保できる状態です。"
    }
  }
}

struct HomeView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      NavigationStack {
        HomeView(
          repository: MockHomeRepository(snapshot: .workingSample),
          screenTime: MobileScreenTimeController())
      }
      .previewDisplayName("作業中")
      NavigationStack {
        HomeView(
          repository: MockHomeRepository(snapshot: .pausedSample),
          screenTime: MobileScreenTimeController())
      }
      .previewDisplayName("一時停止中")
      NavigationStack {
        HomeView(
          repository: MockHomeRepository(snapshot: .noSessionSample),
          screenTime: MobileScreenTimeController())
      }
      .previewDisplayName("セッションなし")
    }
  }
}
