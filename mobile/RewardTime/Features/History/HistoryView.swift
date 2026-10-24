import Combine
import SwiftUI

@MainActor
private final class HistoryViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case work = "作業"
        case rewards = "報酬"
        var id: String { rawValue }
    }

    @Published var section: Section = .work
    @Published private(set) var workItems: [WorkHistoryItem] = []
    @Published private(set) var rewardItems: [RewardHistoryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var nextWorkPageToken = ""
    @Published private(set) var nextRewardPageToken = ""
    @Published private(set) var didLoad = false
    @Published private(set) var isShowingStaleSnapshot = false

    private var repository: (any HistoryRepository)?
    private var loadGeneration = 0
    private var loadMoreGeneration = 0

    func load() async {
        loadGeneration += 1
        loadMoreGeneration += 1
        let requestGeneration = loadGeneration
        let hadLoadedSnapshot = didLoad
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer {
            if requestGeneration == loadGeneration {
                isLoading = false
                didLoad = true
            }
        }

        do {
            let repository = try self.repository ?? ConfiguredHistoryRepository()
            self.repository = repository
            async let workPage = repository.fetchWorkHistory(pageToken: "")
            async let rewardPage = repository.fetchRewardHistory(pageToken: "")
            let (work, rewards) = try await (workPage, rewardPage)
            guard requestGeneration == loadGeneration else { return }
            workItems = work.items
            nextWorkPageToken = work.nextPageToken
            rewardItems = rewards.items
            nextRewardPageToken = rewards.nextPageToken
            isShowingStaleSnapshot = false
        } catch {
            guard requestGeneration == loadGeneration else { return }
            isShowingStaleSnapshot = hadLoadedSnapshot && (!workItems.isEmpty || !rewardItems.isEmpty)
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "履歴を読み込めませんでした。接続状態を確認してください。"
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore else { return }
        loadMoreGeneration += 1
        let requestGeneration = loadGeneration
        let pageGeneration = loadMoreGeneration
        let requestedSection = section
        let token = requestedSection == .work ? nextWorkPageToken : nextRewardPageToken
        guard !token.isEmpty else { return }
        isLoadingMore = true
        errorMessage = nil
        defer {
            if pageGeneration == loadMoreGeneration { isLoadingMore = false }
        }

        do {
            let repository = try self.repository ?? ConfiguredHistoryRepository()
            self.repository = repository
            switch requestedSection {
            case .work:
                let page = try await repository.fetchWorkHistory(pageToken: token)
                guard requestGeneration == loadGeneration, pageGeneration == loadMoreGeneration else { return }
                workItems.append(contentsOf: page.items)
                nextWorkPageToken = page.nextPageToken
            case .rewards:
                let page = try await repository.fetchRewardHistory(pageToken: token)
                guard requestGeneration == loadGeneration, pageGeneration == loadMoreGeneration else { return }
                rewardItems.append(contentsOf: page.items)
                nextRewardPageToken = page.nextPageToken
            }
        } catch {
            guard requestGeneration == loadGeneration, pageGeneration == loadMoreGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "続きの履歴を読み込めませんでした。"
        }
    }
}

struct HistoryView: View {
    @StateObject private var model = HistoryViewModel()

    var body: some View {
        ScreenContainer {
            Picker("履歴の種類", selection: $model.section) {
                ForEach(HistoryViewModel.Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)

            if let errorMessage = model.errorMessage {
                SurfaceCard {
                    Label("履歴を読み込めませんでした", systemImage: "wifi.exclamationmark")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                    if model.isShowingStaleSnapshot {
                        Text("前回読み込んだ履歴を表示しています。最新の状態ではない可能性があります。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    Button("再読み込み") { Task { await model.load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primary)
                }
            }

            if model.isLoading && !model.didLoad {
                SurfaceCard {
                    ProgressView("履歴を読み込み中…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if model.section == .work {
                workHistory
            } else {
                rewardHistory
            }

            if hasMore {
                Button {
                    Task { await model.loadMore() }
                } label: {
                    Label(model.isLoadingMore ? "読み込み中…" : "さらに読み込む", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.isLoadingMore)
            }
        }
        .refreshable { await model.load() }
        .task { if !model.didLoad { await model.load() } }
        .onReceive(NotificationCenter.default.publisher(for: .mobileAuthenticationChanged)) { _ in
            Task { await model.load() }
        }
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var workHistory: some View {
        if model.workItems.isEmpty && model.didLoad && model.errorMessage == nil {
            emptyState("作業履歴はありません")
        } else {
            ForEach(model.workItems) { item in
                SurfaceCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.taskName)
                                .font(.headline)
                            Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                        Text(sessionStatus(item.status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                    }

                    HStack(spacing: 16) {
                        metric("作業", seconds: item.workSeconds)
                        metric("稼働", seconds: item.activeSeconds)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        rewardMetric("獲得", seconds: item.earnedSeconds, color: AppTheme.teal)
                        rewardMetric("利用", seconds: item.spentSeconds, color: AppTheme.primary)
                        rewardMetric("破棄", seconds: item.discardedSeconds, color: AppTheme.secondaryInk)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rewardHistory: some View {
        if model.rewardItems.isEmpty && model.didLoad && model.errorMessage == nil {
            emptyState("報酬の履歴はありません")
        } else {
            ForEach(model.rewardItems) { item in
                SurfaceCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(transactionTitle(item.type))
                                .font(.headline)
                            Text(item.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                        Text(signedDuration(item.amountSeconds))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(item.amountSeconds >= 0 ? AppTheme.teal : AppTheme.ink)
                    }
                    Text("取引後の残高 \(formattedDuration(item.balanceAfterSeconds))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
    }

    private var hasMore: Bool {
        !(model.section == .work ? model.nextWorkPageToken : model.nextRewardPageToken).isEmpty
    }

    private func emptyState(_ text: String) -> some View {
        SurfaceCard {
            Label(text, systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private func metric(_ label: String, seconds: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Text(formattedDuration(seconds)).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private func rewardMetric(_ label: String, seconds: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Text(formattedDuration(seconds)).font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
    }

    private func sessionStatus(_ status: String) -> String {
        switch status {
        case "SESSION_STATUS_RUNNING": "作業中"
        case "SESSION_STATUS_PAUSED": "一時停止"
        case "SESSION_STATUS_FINALIZED": "完了"
        case "SESSION_STATUS_ABORTED": "中止"
        default: "記録"
        }
    }

    private func transactionTitle(_ type: String) -> String {
        switch type {
        case "EARN": "報酬を獲得"
        case "SPEND": "利用枠を確保"
        case "DISCARD": "未使用残高を破棄"
        case "REFUND": "返還"
        case "ADJUST": "残高調整"
        default: "報酬取引"
        }
    }

    private func signedDuration(_ seconds: Int64) -> String {
        let sign = seconds > 0 ? "+" : (seconds < 0 ? "−" : "")
        return sign + formattedDuration(abs(seconds))
    }

    private func formattedDuration(_ seconds: Int64) -> String {
        let minutes = max(seconds, 0) / 60
        let remainder = max(seconds, 0) % 60
        if remainder == 0 { return "\(minutes)分" }
        return "\(minutes)分\(remainder)秒"
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { HistoryView() }
    }
}
