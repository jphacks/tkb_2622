import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel

    init(repository: any HomeRepository = MockHomeRepository()) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(repository: repository))
    }

    var body: some View {
        ScreenContainer {
            SampleNotice(title: "サンプルデータ・API未接続")

#if DEBUG
            previewControls
#endif

            switch viewModel.state {
            case .loading:
                ProgressView("状態を読み込み中…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            case .loaded(let snapshot):
                sessionCard(snapshot)
                workTimeCard(snapshot)
                rewardBalanceCard(snapshot)
                restrictedAppsCard(snapshot)
                restrictionStateCard(snapshot)
                breakAction(snapshot)
            case .failed:
                errorCard
            }
        }
        .navigationTitle("Focus Link")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Label("サンプル \(viewModel.lastUpdatedTime)", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .labelStyle(.titleAndIcon)
            }
        }
        .task {
            if case .loading = viewModel.state {
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }

#if DEBUG
    private var previewControls: some View {
        SurfaceCard {
            Label("表示するサンプル状態", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.bold))
            Menu("画面状態を選ぶ") {
                Button("08 作業中・制限中") { viewModel.showPreview(.workingSample) }
                Button("10 一時停止中") { viewModel.showPreview(.pausedSample) }
                Button("11 小休憩中") { viewModel.showPreview(.releasedSample) }
                Button("08 セッションなし") { viewModel.showPreview(.noSessionSample) }
            }
            .font(.subheadline.weight(.semibold))
            NavigationLink {
                RestrictionShieldPreview()
            } label: {
                Label("09 制限画面のプレビュー", systemImage: "lock.iphone")
                    .font(.footnote.weight(.medium))
            }
        }
    }
#endif

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

            Text(sessionDescription(snapshot.sessionStatus))
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private func workTimeCard(_ snapshot: MobileHomeSnapshot) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 5) {
                Text("計測時間")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryInk)
                Text(formattedWorkTime(snapshot.elapsedWorkMinutes))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("elapsedWorkTime")
            }

            if let elapsed = snapshot.elapsedWorkMinutes,
               let minimum = snapshot.minimumWorkMinutes {
                let remaining = max(minimum - elapsed, 0)
                Text(remaining > 0
                     ? "最小作業時間 \(minimum)分 まで あと \(remaining)分"
                     : "最小作業時間 \(minimum)分を達成")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryInk)
            } else {
                Text("作業セッションが始まると計測時間が表示されます。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }

    private func rewardBalanceCard(_ snapshot: MobileHomeSnapshot) -> some View {
        SurfaceCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("報酬の残高")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryInk)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(snapshot.rewardBalanceMinutes.formatted())
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .accessibilityIdentifier("rewardBalanceMinutes")
                        Text("分")
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.teal)
                }
                Spacer(minLength: 8)
                Image(systemName: "hourglass")
                    .font(.title2)
                    .foregroundStyle(AppTheme.teal)
                    .padding(14)
                    .background(AppTheme.mint, in: Circle())
            }

            Text("今回の報酬は作業セッション中の小休憩に使えます。終了・中止時に未使用分は破棄されます。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restrictedAppsCard(_ snapshot: MobileHomeSnapshot) -> some View {
        SurfaceCard {
            HStack {
                Text("制限中のアプリ")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(snapshot.restrictedApps.count)個")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.lavender, in: Capsule())
            }

            if snapshot.restrictedApps.isEmpty {
                Text("制限対象のアプリはありません。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(snapshot.restrictedApps, id: \.self) { app in
                        Label(app, systemImage: "app.fill")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            Text("iPhoneの標準アプリ（Safariを除く）はいつでも使えます。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private func restrictionStateCard(_ snapshot: MobileHomeSnapshot) -> some View {
        SurfaceCard {
            Label("iPhoneの適用状態", systemImage: "lock.iphone")
                .font(.subheadline.weight(.bold))

            switch snapshot.restrictionStatus {
            case .unrestricted:
                Text("制限解除済み")
                    .foregroundStyle(AppTheme.secondaryInk)
            case .restricted:
                Text("制限中")
                    .foregroundStyle(AppTheme.teal)
            case .temporarilyReleased(let endsAt):
                Text("一時解除中・終了予定 \(endsAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(AppTheme.teal)
            case .notConfirmed:
                Text("iPhoneでの適用を確認できていません")
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            Text("サーバーの希望状態とiPhoneでの適用確認は分けて表示します。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private func breakAction(_ snapshot: MobileHomeSnapshot) -> some View {
        if snapshot.sessionStatus == .paused {
            NavigationLink {
                UsageReservationView(balanceMinutes: snapshot.rewardBalanceMinutes)
            } label: {
                Label("残高を使う", systemImage: "cup.and.saucer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
            .disabled(snapshot.rewardBalanceMinutes <= 0)
        } else {
            Label {
                Text(snapshot.sessionStatus == .working
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

    private var errorCard: some View {
        SurfaceCard {
            Label("状態を読み込めませんでした", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text("接続状態を確認して、もう一度お試しください。")
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
            NavigationStack { HomeView(repository: MockHomeRepository(snapshot: .workingSample)) }
                .previewDisplayName("作業中")
            NavigationStack { HomeView(repository: MockHomeRepository(snapshot: .pausedSample)) }
                .previewDisplayName("一時停止中")
            NavigationStack { HomeView(repository: MockHomeRepository(snapshot: .noSessionSample)) }
                .previewDisplayName("セッションなし")
        }
    }
}
