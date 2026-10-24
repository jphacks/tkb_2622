import SwiftUI

struct HistoryView: View {
    var body: some View {
        ScreenContainer {
            SampleNotice(title: "履歴API未接続")
            SurfaceCard {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.primary)
                Text("作業履歴")
                    .font(.title3.weight(.bold))
                Text("履歴画面の個別モックとAPI契約がまだありません。報酬の獲得・利用・破棄を、仕様が決まる前に作り込まずにいます。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { HistoryView() }
    }
}
