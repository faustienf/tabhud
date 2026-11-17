import SwiftUI

/// The same upright, optically centered star in the rail, app badge and favorites hub.
/// Explicit bounds keep tiny symbols centered without a text font's bearings or baseline.
struct FavoriteGlyph: View {
    var isFilled = true

    var body: some View {
        GeometryReader { geometry in
            let lineWidth = max(0.8, min(geometry.size.width, geometry.size.height) * 0.08)
            if isFilled {
                FavoriteStar()
                    .padding(lineWidth / 2)
            } else {
                FavoriteStar()
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                    .padding(lineWidth / 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct FavoriteStar: Shape {
    func path(in rect: CGRect) -> Path {
        // Five outer vertices, starting at twelve o'clock. Normalize their visible bounds,
        // whose vertical center differs from the center of the circumscribed circle.
        let halfWidth = sin(2 * Double.pi / 5)
        let bottom = cos(Double.pi / 5)
        var path = Path()
        for vertex in 0..<10 {
            let angle = -Double.pi / 2 + Double(vertex) * Double.pi / 5
            let radius = vertex.isMultiple(of: 2) ? 1.0 : 0.45
            let point = CGPoint(x: rect.midX + radius * cos(angle) / halfWidth * rect.width / 2,
                                y: rect.minY + (radius * sin(angle) + 1) / (1 + bottom) * rect.height)
            if vertex == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
