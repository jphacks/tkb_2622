import SwiftUI

/// Focus Link mark drawn from focuslink-mark-currentColor.svg (viewBox 8 8 84 84).
struct FocusLinkMark: View {
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
