import SwiftUI

/// Static visual reference for mock 09. This is not an iOS Screen Time shield.
struct RestrictionShieldPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            FocusLinkMark()
                .foregroundStyle(AppTheme.primary)
                .frame(width: 38, height: 38)
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

            Text("静的な画面プレビューです。実際の制限表示は対象アプリを開いて確認してください。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .foregroundStyle(AppTheme.ink)
    }
}

/// Focus Link mark drawn from focuslink-mark-currentColor.svg (viewBox 8 8 84 84).
private struct FocusLinkMark: View {
    var body: some View {
        ZStack {
            // The SVG strokes the head with width 8, so draw its outer and inner edges as an even-odd ring.
            FocusLinkMarkShape(rects: [(26, 10, 48, 36, 10), (34, 18, 32, 20, 2)])
                .fill(style: FillStyle(eoFill: true))
            FocusLinkMarkShape(rects: [(38, 45, 24, 6, 3), (45, 48, 10, 42, 5), (51, 66, 14, 7, 3), (51, 78, 10, 7, 3)])
                .fill()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct FocusLinkMarkShape: Shape {
    let rects: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat)]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 84
        var path = Path()
        for item in rects {
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX + (item.x - 8) * scale,
                    y: rect.minY + (item.y - 8) * scale,
                    width: item.width * scale,
                    height: item.height * scale
                ),
                cornerSize: CGSize(width: item.radius * scale, height: item.radius * scale)
            )
        }
        return path
    }
}

struct RestrictionShieldPreview_Previews: PreviewProvider {
    static var previews: some View {
        RestrictionShieldPreview()
            .previewDisplayName("09 Shield（静的プレビュー）")
    }
}
