import Combine
import SwiftUI

@MainActor
final class UsageReservationViewModel: ObservableObject {
    let balanceMinutes: Int
    let options = [5, 10, 15, 30]

    @Published var selectedMinutes = 10
    @Published var isNotConnectedAlertPresented = false

    init(balanceMinutes: Int) {
        self.balanceMinutes = balanceMinutes
        if balanceMinutes < selectedMinutes {
            selectedMinutes = options.last(where: { $0 <= balanceMinutes }) ?? 0
        }
    }

    func requestReservation() {
        isNotConnectedAlertPresented = true
    }
}

struct UsageReservationView: View {
    @StateObject private var viewModel: UsageReservationViewModel

    init(balanceMinutes: Int) {
        _viewModel = StateObject(wrappedValue: UsageReservationViewModel(balanceMinutes: balanceMinutes))
    }

    var body: some View {
        ScreenContainer {
            SampleNotice(title: "小休憩の画面案・API未接続")

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
                                if viewModel.selectedMinutes == minutes {
                                    Image(systemName: "checkmark")
                                }
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
                                    .strokeBorder(
                                        viewModel.selectedMinutes == minutes ? AppTheme.teal : .clear,
                                        lineWidth: 1.5
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(minutes > viewModel.balanceMinutes)
                        .opacity(minutes > viewModel.balanceMinutes ? 0.4 : 1)
                    }
                }
            }

            SurfaceCard {
                Label("制限中のアプリを実際に使っている時間だけ減ります。", systemImage: "checkmark.circle.fill")
                Label("標準アプリ（Safariを除く）の利用は減りません。", systemImage: "checkmark.circle.fill")
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryInk)

            SurfaceCard {
                Label("Macで作業を始めるか再開すると、この利用枠の残りは破棄されます。未充当の報酬残高はセッション中保持されます。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            Button {
                viewModel.requestReservation()
            } label: {
                Text("\(viewModel.selectedMinutes)分使う（API未接続）")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
            .disabled(viewModel.selectedMinutes <= 0)

            NavigationLink("利用中画面のサンプルを見る") {
                ActiveUsageView()
            }
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("残高を使う")
        .navigationBarTitleDisplayMode(.inline)
        .alert("まだ利用枠を確保できません", isPresented: $viewModel.isNotConnectedAlertPresented) {
            Button("閉じる", role: .cancel) { }
        } message: {
            Text("利用枠を確保するAPIが未実装のため、残高は変更していません。")
        }
    }
}

struct ActiveUsageView: View {
    var body: some View {
        ScreenContainer {
            SampleNotice(title: "利用中画面のサンプル・計測未接続")

            SurfaceCard {
                HStack {
                    Label("解除を確認済み", systemImage: "checkmark.shield.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.teal)
                    Spacer()
                    Text("サンプル")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Text("利用中 ・ Mac は一時停止中")
                    .font(.headline)
            }

            SurfaceCard {
                Text("枠の残り")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryInk)
                Text("07:12 / 10:00")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primary)
                Text("使っていない間は減りません")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            SurfaceCard {
                Text("報酬の残高 22分")
                    .font(.headline)
                    .foregroundStyle(AppTheme.teal)
                Text("この枠で使った時間 2分48秒")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            SurfaceCard {
                Text("Macで作業を再開すると、この利用枠の残りを破棄して再び制限します。未充当の残高は作業セッションが続く間保持します。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .navigationTitle("利用中")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UsageReservationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { UsageReservationView(balanceMinutes: 32) }
        NavigationStack { ActiveUsageView() }
    }
}
