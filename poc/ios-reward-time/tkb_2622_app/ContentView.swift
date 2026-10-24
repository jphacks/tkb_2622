import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: RewardStore
    @State private var minutesInput = ""

    init() {
        _store = StateObject(wrappedValue: RewardStore(repository: UserDefaultsRewardRepository()))
    }

    init(store: RewardStore) {
        _store = StateObject(wrappedValue: store)
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
                        Text("PoC表示のみ（実際のアプリ制限は未接続）")
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
            Task {
                await store.load()
            }
        }
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
