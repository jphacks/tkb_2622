import SwiftUI

/// Static visual reference for mock 09. This is not an iOS Screen Time shield.
struct RestrictionShieldPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "leaf.fill")
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 88, height: 88)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))

            Text("YouTube は\nいま制限中です")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 20)

            Text("Mac で作業中です。\n一時停止すると、残高 32分 を使えます。")
                .font(.body)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundStyle(AppTheme.secondaryInk)
                .padding(.top, 12)

            Spacer()

            Text("FamilyControls未接続の画面プレビュー")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .foregroundStyle(AppTheme.ink)
    }
}

struct RestrictionShieldPreview_Previews: PreviewProvider {
    static var previews: some View {
        RestrictionShieldPreview()
            .previewDisplayName("09 Shield画面案（静的プレビュー）")
    }
}
