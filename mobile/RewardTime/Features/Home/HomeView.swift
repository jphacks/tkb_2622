import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel

    init(repository: any HomeRepository = MockHomeRepository()) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    developmentNotice

                    switch viewModel.state {
                    case .loading:
                        loadingState
                    case .loaded(let snapshot):
                        sessionCard(snapshot)
                        balanceCard(snapshot)
                        restrictionCard(snapshot)
                        syncInformation(snapshot)
                    case .failed:
                        errorState
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("ホーム")
            .refreshable {
                await viewModel.load()
            }
            .task {
                if case .loading = viewModel.state {
                    await viewModel.load()
                }
            }
        }
    }

    private var developmentNotice: some View {
        Label {
            Text("開発用の仮データを表示しています")
                .font(.footnote.weight(.medium))
        } icon: {
            Image(systemName: "wrench.and.screwdriver.fill")
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sessionCard(_ snapshot: MobileHomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Macの作業状態", systemImage: "laptopcomputer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge(sessionTitle(snapshot.sessionStatus), color: sessionColor(snapshot.sessionStatus))
            }

            Text(sessionDescription(snapshot.sessionStatus))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("作業状態はMacとの同期後に更新されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func balanceCard(_ snapshot: MobileHomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("今回の報酬残高", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.rewardBalanceMinutes.formatted())
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("rewardBalanceMinutes")
                Text("分")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("報酬は作業セッション中の小休憩に利用できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
    }

    private func restrictionCard(_ snapshot: MobileHomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("iPhoneの制限状態", systemImage: "lock.iphone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            switch snapshot.restrictionStatus {
            case .restricted:
                Label("制限中", systemImage: "lock.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.green)
            case .temporarilyReleased(let endsAt):
                Label("一時解除中", systemImage: "lock.open.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.orange)
                Text("解除終了予定: \(endsAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .notConfirmed:
                Label("適用状態を確認できません", systemImage: "questionmark.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("サーバーの希望状態とiPhoneでの適用確認は別々に表示します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func syncInformation(_ snapshot: MobileHomeSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text("最終更新: \(snapshot.lastSyncedAt.formatted(date: .omitted, time: .shortened))")
            Spacer()
            Text("サンプル")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }

    private var loadingState: some View {
        ProgressView("状態を読み込み中…")
            .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var errorState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("状態を読み込めませんでした")
                .font(.headline)
            Text("接続状態を確認して、もう一度お試しください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("再読み込み") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func sessionTitle(_ status: SessionStatus) -> String {
        switch status {
        case .noSession: "未開始"
        case .working: "作業中"
        case .paused: "一時停止中"
        }
    }

    private func sessionDescription(_ status: SessionStatus) -> String {
        switch status {
        case .noSession: "作業セッションはありません。"
        case .working: "Macで作業しています。"
        case .paused: "Macで作業を一時停止しています。"
        }
    }

    private func sessionColor(_ status: SessionStatus) -> Color {
        switch status {
        case .noSession: .secondary
        case .working: .green
        case .paused: .orange
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
