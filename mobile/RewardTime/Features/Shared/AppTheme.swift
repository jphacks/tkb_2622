import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.969, green: 0.961, blue: 1.0)
    static let ink = Color(red: 0.118, green: 0.106, blue: 0.227)
    static let secondaryInk = Color(red: 0.369, green: 0.353, blue: 0.471)
    static let primary = Color(red: 0.357, green: 0.294, blue: 0.859)
    static let teal = Color(red: 0.043, green: 0.498, blue: 0.420)
    static let mint = Color(red: 0.867, green: 0.965, blue: 0.941)
    static let lavender = Color(red: 0.925, green: 0.914, blue: 1.0)
    static let yellow = Color(red: 1.0, green: 0.945, blue: 0.761)
}

struct ScreenContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .foregroundStyle(AppTheme.ink)
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SampleNotice: View {
    var title = "開発用のサンプル表示です"

    var body: some View {
        Label(title, systemImage: "wrench.and.screwdriver.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.lavender, in: RoundedRectangle(cornerRadius: 14))
    }
}
