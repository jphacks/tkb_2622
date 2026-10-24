import SwiftUI

private struct NotificationExample: Identifiable {
    let id: String
    let device: String
    let time: String
    let title: String
    let body: String
    let isDeliveredDuringWork: Bool
}

struct NotificationExamplesView: View {
    private let examples = [
        NotificationExample(
            id: "group-start",
            device: "Mac・iPhone",
            time: "8:50",
            title: "はるとさんが作業を始めました",
            body: "タップすると開始画面を開きます。",
            isDeliveredDuringWork: true
        ),
        NotificationExample(
            id: "reward-earned",
            device: "iPhone",
            time: "14:21",
            title: "報酬 +40分 が確定しました",
            body: "残高は 72分 です。",
            isDeliveredDuringWork: false
        ),
        NotificationExample(
            id: "usage-started",
            device: "iPhone",
            time: "15:02",
            title: "利用を開始しました",
            body: "10分の枠を使っている時間だけ減ります。",
            isDeliveredDuringWork: false
        ),
        NotificationExample(
            id: "usage-finished",
            device: "iPhone",
            time: "15:30",
            title: "利用枠を使い切りました",
            body: "アプリを再び制限しました。",
            isDeliveredDuringWork: false
        )
    ]

    var body: some View {
        ScreenContainer {
            SampleNotice(title: "通知例・実際には送信しません")

            ForEach(examples) { example in
                SurfaceCard {
                    HStack {
                        Label(example.device, systemImage: "bell.badge")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryInk)
                        Spacer()
                        Text(example.time)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    Text(example.title)
                        .font(.subheadline.weight(.bold))
                    Text(example.body)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)

                    Label(
                        example.isDeliveredDuringWork ? "作業中も通知する案" : "作業中・一時停止中は通知しない",
                        systemImage: example.isDeliveredDuringWork ? "checkmark.circle.fill" : "bell.slash.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(example.isDeliveredDuringWork ? AppTheme.teal : AppTheme.secondaryInk)
                    .padding(.top, 3)
                }
            }

            SurfaceCard {
                Text("作業中・一時停止中は報酬確定や利用開始の通知を出さず、あとから再送もしません。グループの作業開始通知は作業中も届く案です。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("通知の例")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationExamplesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { NotificationExamplesView() }
    }
}
