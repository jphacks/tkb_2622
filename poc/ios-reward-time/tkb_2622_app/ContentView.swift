import SwiftUI
import FamilyControls

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: RewardStore
    @StateObject private var screenTime: ScreenTimePrototype
    @StateObject private var rewardSync: RewardSyncPrototype
    @State private var minutesInput = ""
    @State private var isFamilyActivityPickerPresented = false

    init() {
        _store = StateObject(wrappedValue: RewardStore(repository: UserDefaultsRewardRepository()))
        _screenTime = StateObject(wrappedValue: ScreenTimePrototype())
        _rewardSync = StateObject(wrappedValue: RewardSyncPrototype())
    }

    init(store: RewardStore) {
        _store = StateObject(wrappedValue: store)
        _screenTime = StateObject(wrappedValue: ScreenTimePrototype())
        _rewardSync = StateObject(wrappedValue: RewardSyncPrototype())
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Form {
                    Section("報酬残高（仮）") {
                        Text("\(store.snapshot.balanceMinutes) 分")
                            .font(.largeTitle.bold())
                            .accessibilityIdentifier("rewardBalance")
                    }

                    Section("利用状態") {
                        Text("報酬の期限とアプリ制限は未連動です。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        switch store.snapshot.unlockStatus(at: timeline.date) {
                        case .locked:
                            Label("制限中", systemImage: "lock.fill")
                        case .unlocked(let endsAt):
                            Label("解除中", systemImage: "lock.open.fill")
                            Text("終了予定: \(endsAt.formatted(date: .abbreviated, time: .shortened))")
                            Text(endsAt, style: .timer)
                                .monospacedDigit()
                        case .expired(let endsAt):
                            Label("期限切れ・制限中", systemImage: "lock.fill")
                            Text("解除終了: \(endsAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }

                    Section("報酬を使う（PoC）") {
                        TextField("利用時間（分）", text: $minutesInput)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("redemptionMinutes")

                        Button("報酬を使う") {
                            guard let minutes = Int(minutesInput) else {
                                store.showError("利用時間を分単位の整数で入力してください。")
                                return
                            }
                            Task {
                                await store.redeem(minutes: minutes)
                            }
                        }
                        .disabled(store.isLoading)
                        .accessibilityIdentifier("redeemReward")
                    }

                    Section("アプリ制限の技術検証") {
                        Text("本人認可と選択したアプリへの制限を実機で確認します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        LabeledContent("Family Controls") {
                            Text(screenTime.authorizationStatusLabel)
                        }

                        Button("本人利用の認可を要求") {
                            Task {
                                await screenTime.requestAuthorization()
                            }
                        }
                        .disabled(screenTime.isRequestingAuthorization)

                        Button("制限するアプリを選択") {
                            isFamilyActivityPickerPresented = true
                        }
                        .disabled(!screenTime.isAuthorized)

                        Text("選択中: \(screenTime.selectedApplicationCount) 個のアプリ")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("選択したアプリを制限") {
                            screenTime.applyShield()
                        }
                        .disabled(!screenTime.canApplyShield)

                        Button("このPoCの制限を解除", role: .destructive) {
                            screenTime.clearShield()
                        }
                        .disabled(!screenTime.isAuthorized)

                        if let message = screenTime.statusMessage {
                            Text(message)
                                .font(.footnote)
                                .accessibilityIdentifier("screenTimeStatus")
                        }

                        if let errorMessage = screenTime.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    Section("Mac/API通信（PoC）") {
                        Text("Macが送った仮データをAPIから取得します。ローカルの仮残高は変更しません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("http://MacのIPアドレス:8787", text: $rewardSync.serverAddress)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("APIから報酬状態を取得") {
                            Task {
                                await rewardSync.fetchSnapshot()
                            }
                        }
                        .disabled(rewardSync.isLoading)

                        if rewardSync.isLoading {
                            ProgressView("APIに接続中…")
                        }

                        if let snapshot = rewardSync.receivedSnapshot {
                            LabeledContent("APIの仮残高", value: "\(snapshot.balanceMinutes) 分")
                            LabeledContent(
                                "APIの解除終了予定",
                                value: snapshot.unlockEndsAt?.formatted(date: .abbreviated, time: .shortened) ?? "未設定"
                            )
                        }

                        if let statusMessage = rewardSync.statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                        }

                        if let errorMessage = rewardSync.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .overlay {
                    if store.isLoading {
                        ProgressView("読み込み中…")
                    }
                }
            }
            .navigationTitle("報酬時間")
        }
        .task {
            await store.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            screenTime.refreshAuthorizationStatus()
            Task {
                await store.load()
            }
        }
        .familyActivityPicker(
            isPresented: $isFamilyActivityPickerPresented,
            selection: $screenTime.selection
        )
        .alert("操作できません", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(store: RewardStore(repository: InMemoryRewardRepository()))
    }
}
