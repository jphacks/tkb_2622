import Combine
import FamilyControls
import SwiftUI

struct ActiveUsageGrant: Hashable, Identifiable {
    let id: String
    let reservedSeconds: Int64
    let deviceID: String
    let controlRevision: Int64
}

@MainActor
final class UsageReservationViewModel: ObservableObject {
    let balanceMinutes: Int
    let options = [5, 10, 15, 30]

    @Published var selectedMinutes = 10
    @Published private(set) var isReserving = false
    @Published private(set) var reservationError: String?
    @Published var activeGrant: ActiveUsageGrant?

    private let sessionID: String
    private let sessionVersion: Int64
    private let screenTime: MobileScreenTimeController
    private let defaults = UserDefaults.standard

    init(
        balanceMinutes: Int,
        sessionID: String,
        sessionVersion: Int64,
        screenTime: MobileScreenTimeController
    ) {
        self.balanceMinutes = balanceMinutes
        self.sessionID = sessionID
        self.sessionVersion = sessionVersion
        self.screenTime = screenTime
        if balanceMinutes < selectedMinutes {
            selectedMinutes = options.last(where: { $0 <= balanceMinutes }) ?? 0
        }
        if defaults.string(forKey: "mobile.usage.reserve.pendingOperationID") != nil,
           let pendingSeconds = defaults.object(forKey: "mobile.usage.reserve.pendingSeconds") as? Int {
            selectedMinutes = pendingSeconds / 60
        }
    }

    var hasPendingRequest: Bool {
        guard let operationID = defaults.string(forKey: "mobile.usage.reserve.pendingOperationID") else { return false }
        return !operationID.isEmpty
    }

    var canReserve: Bool {
        !isReserving && selectedMinutes > 0 && eligibility == .allowed && sessionCanReserve
    }

    private var sessionCanReserve: Bool {
        !sessionID.isEmpty && screenTime.isAuthorized
            && screenTime.restrictionMode == .selectedApplications
            && screenTime.restrictedApplicationCount > 0
            && !screenTime.hasUnsupportedTargets
            && ScreenTimeSharedStorage.defaults.string(forKey: "mobile.usage.activeGrantID") == nil
    }

    private var eligibility: UsageReservationEligibility {
        UsageReservationEligibility.evaluate(
            selectedMinutes: selectedMinutes,
            balanceMinutes: balanceMinutes,
            pendingOperationID: defaults.string(forKey: "mobile.usage.reserve.pendingOperationID"),
            pendingSeconds: defaults.object(forKey: "mobile.usage.reserve.pendingSeconds") as? Int
        )
    }

    var unavailableReason: String? {
        if sessionID.isEmpty { return "作業セッションを再読み込みしてください。" }
        if !screenTime.isAuthorized { return "先に設定からスクリーンタイムを許可してください。" }
        if screenTime.restrictionMode != .selectedApplications {
            return "利用時間を正確に計測するため、「選んだアプリを制限」にしてください。"
        }
        if screenTime.restrictedApplicationCount == 0 {
            return "利用時間を計測するアプリを設定から選んでください。"
        }
        if screenTime.hasUnsupportedTargets {
            return "現在は選択したアプリだけを利用時間の計測対象にできます。"
        }
        if eligibility == .invalidPendingRequest {
            return "前回の予約結果を確認できません。アプリを再起動して、同じ予約を再試行してください。"
        }
        if eligibility == .insufficientBalance { return "残高を超える時間は選べません。" }
        if ScreenTimeSharedStorage.defaults.string(forKey: "mobile.usage.activeGrantID") != nil {
            return "利用中の枠があります。先に利用状況を同期してください。"
        }
        return nil
    }

    func requestReservation() async {
        guard canReserve else {
            reservationError = unavailableReason
            return
        }
        isReserving = true
        reservationError = nil
        defer { isReserving = false }

        let savedOperationID = defaults.string(forKey: "mobile.usage.reserve.pendingOperationID")
        let operationID = savedOperationID ?? UUID().uuidString.lowercased()
        let requestedSeconds = savedOperationID == nil
            ? selectedMinutes * 60
            : (defaults.object(forKey: "mobile.usage.reserve.pendingSeconds") as? Int ?? selectedMinutes * 60)
        defaults.set(operationID, forKey: "mobile.usage.reserve.pendingOperationID")
        defaults.set(requestedSeconds, forKey: "mobile.usage.reserve.pendingSeconds")

        do {
            try DeviceActivityUsageMonitor().start(
                operationID: operationID,
                reservedSeconds: requestedSeconds,
                selection: screenTime.selection,
                alwaysAllowedSelection: screenTime.alwaysAllowedSelection
            )
            let repository = try ConfiguredUsageGrantRepository()
            let result = try await repository.reserve(
                operationID: operationID,
                sessionID: sessionID,
                expectedSessionVersion: sessionVersion,
                requestedSeconds: Int64(requestedSeconds)
            )
            guard result.desiredMode == "DESIRED_MODE_TIMED_UNLOCK",
                  result.grant.id.isEmpty == false else {
                reservationError = "backendが利用枠を有効にしませんでした。ホームを再読み込みしてください。"
                return
            }

            defaults.removeObject(forKey: "mobile.usage.reserve.pendingOperationID")
            defaults.removeObject(forKey: "mobile.usage.reserve.pendingSeconds")
            ScreenTimeSharedStorage.defaults.set(screenTime.restrictionMode.rawValue, forKey: "mobile.screenTime.restrictionMode")
            ScreenTimeSharedStorage.defaults.set(result.deviceID, forKey: "mobile.usage.deviceID")
            DeviceActivityUsageMonitor().activate(
                grantID: result.grant.id,
                controlRevision: result.controlRevision
            )
            screenTime.clearRestriction()
            activeGrant = ActiveUsageGrant(
                id: result.grant.id,
                reservedSeconds: result.grant.reservedSeconds,
                deviceID: result.deviceID,
                controlRevision: result.controlRevision
            )

            do {
                try await repository.reportActivation(
                    deviceID: result.deviceID,
                    grantID: result.grant.id,
                    controlRevision: result.controlRevision,
                    shieldStatus: "SHIELD_STATUS_UNSHIELDED"
                )
            } catch {
                screenTime.applyRestriction()
                let detail = (error as? LocalizedError)?.errorDescription
                    ?? "接続状態を確認してください。"
                reservationError = "利用枠は確保しましたが、解除状態をbackendへ報告できませんでした。通信を確認して利用中画面から再同期してください。\n\(detail)"
            }
        } catch {
            let canDiscardPendingOperation = error is UsageGrantRepositoryError
                || error is DeviceActivityUsageMonitorError
                || UsageReservationFailurePolicy.shouldDiscardPendingOperation(after: error)
            if canDiscardPendingOperation {
                DeviceActivityUsageMonitor().stop()
                defaults.removeObject(forKey: "mobile.usage.reserve.pendingOperationID")
                defaults.removeObject(forKey: "mobile.usage.reserve.pendingSeconds")
            }
            let detail = (error as? LocalizedError)?.errorDescription
                ?? "接続状態を確認してください。"
            if canDiscardPendingOperation {
                reservationError = detail
            } else {
                reservationError = "利用枠の確保結果が未確定です。同じ時間のまま再試行してください。\n\(detail)"
            }
        }
    }
}

struct UsageReservationView: View {
    @StateObject private var viewModel: UsageReservationViewModel
    @ObservedObject private var screenTime: MobileScreenTimeController

    init(
        balanceMinutes: Int,
        sessionID: String,
        sessionVersion: Int64,
        screenTime: MobileScreenTimeController
    ) {
        _viewModel = StateObject(wrappedValue: UsageReservationViewModel(
            balanceMinutes: balanceMinutes,
            sessionID: sessionID,
            sessionVersion: sessionVersion,
            screenTime: screenTime
        ))
        _screenTime = ObservedObject(wrappedValue: screenTime)
    }

    var body: some View {
        ScreenContainer {
            SurfaceCard {
                Text("報酬の残高")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryInk)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(viewModel.balanceMinutes.formatted())
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("分")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(AppTheme.teal)
            }

            SurfaceCard {
                Text("今回使う時間")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(viewModel.options, id: \.self) { minutes in
                        Button {
                            viewModel.selectedMinutes = minutes
                        } label: {
                            HStack {
                                Text("\(minutes)分")
                                Spacer()
                                if viewModel.selectedMinutes == minutes { Image(systemName: "checkmark") }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(viewModel.selectedMinutes == minutes ? AppTheme.teal : AppTheme.ink)
                            .padding(14)
                            .background(
                                viewModel.selectedMinutes == minutes ? AppTheme.mint : AppTheme.background,
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 13)
                                    .strokeBorder(viewModel.selectedMinutes == minutes ? AppTheme.teal : .clear, lineWidth: 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(minutes > viewModel.balanceMinutes || viewModel.hasPendingRequest)
                        .opacity(minutes > viewModel.balanceMinutes ? 0.4 : 1)
                    }
                }
            }

            SurfaceCard {
                Label("選んだアプリの画面利用時間をDeviceActivityで計測します。", systemImage: "hourglass")
                Label("計測と自動再制限にはiPhoneのFamily Controls許可が必要です。", systemImage: "checkmark.shield.fill")
                Label("DeviceActivityが1分単位で計測し、backendへは利用中画面の表示中に1分おき、アプリ復帰時に同期します。", systemImage: "clock")
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryInk)

            SurfaceCard {
                Label("Macで作業を始めるか再開すると、残りの利用枠はセッション仕様に従って破棄されます。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            if let reason = viewModel.unavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let reservationError = viewModel.reservationError {
                Text(reservationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await viewModel.requestReservation() }
            } label: {
                Label(
                    viewModel.isReserving
                        ? "利用枠を確保中…"
                        : viewModel.hasPendingRequest
                            ? "\(viewModel.selectedMinutes)分の予約を再試行"
                            : "\(viewModel.selectedMinutes)分の利用枠を確保",
                    systemImage: viewModel.isReserving ? "hourglass" : "lock.open"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
            .disabled(!viewModel.canReserve)

            if let grant = viewModel.activeGrant {
                NavigationLink {
                    ActiveUsageView(grantID: grant.id, reservedSeconds: grant.reservedSeconds)
                } label: {
                    Label("利用状況を確認", systemImage: "timer")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("残高を使う")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private final class ActiveUsageViewModel: ObservableObject {
    @Published private(set) var measuredSeconds = 0
    @Published private(set) var serverStatus = "同期前"
    @Published private(set) var syncMessage: String?
    @Published private(set) var isSyncing = false

    func refresh(grantID: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let shared = ScreenTimeSharedStorage.defaults
        measuredSeconds = shared.integer(forKey: "mobile.usage.measuredSeconds")
        do {
            let repository = try ConfiguredUsageGrantRepository()
            let result = try await repository.synchronizeActiveGrant(grantID: grantID)
            measuredSeconds = result.measuredSeconds
            serverStatus = result.grant.status
            syncMessage = nil
        } catch {
            syncMessage = (error as? LocalizedError)?.errorDescription ?? "APIへ利用状況を同期できません。"
        }
    }
}

struct ActiveUsageView: View {
    let grantID: String
    let reservedSeconds: Int64
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ActiveUsageViewModel()

    var body: some View {
        ScreenContainer {
            SurfaceCard {
                Label("DeviceActivityで計測中", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.teal)
                Text("選択したアプリの画面利用時間を累積します。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let measured = max(
                    viewModel.measuredSeconds,
                    ScreenTimeSharedStorage.defaults.integer(forKey: "mobile.usage.measuredSeconds")
                )
                let remaining = max(Int(reservedSeconds) - measured, 0)
                SurfaceCard {
                    Text("計測済み利用時間")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text(formattedTime(measured))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.primary)
                    Text("残り利用可能枠 約\(formattedTime(remaining))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }

            SurfaceCard {
                HStack {
                    Text("backend状態")
                    Spacer()
                    Text(viewModel.serverStatus)
                        .font(.caption.weight(.semibold))
                }
                if let syncMessage = viewModel.syncMessage {
                    Text(syncMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await viewModel.refresh(grantID: grantID) }
                } label: {
                    Label(viewModel.isSyncing ? "利用状況を同期中…" : "利用状況を同期", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSyncing)
            }

            SurfaceCard {
                Text("残り枠は選択アプリの利用がある場合に減ります。DeviceActivityはバックグラウンドでも計測と自動再制限を行い、backendへはこの画面を表示中に1分おき、アプリ復帰時にも同期します。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .navigationTitle("利用中")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refresh(grantID: grantID)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    return
                }
                guard scenePhase == .active else { continue }
                await viewModel.refresh(grantID: grantID)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh(grantID: grantID) } }
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct UsageReservationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            UsageReservationView(
                balanceMinutes: 32,
                sessionID: "preview-session",
                sessionVersion: 1,
                screenTime: MobileScreenTimeController()
            )
        }
    }
}
