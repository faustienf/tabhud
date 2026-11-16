import SwiftUI

/// CRT texture stays behind all content: the grid and scanlines never cover a screenshot.
struct WheelInstrumentSurface: View {
    let palette: WheelPalette
    var captionRects: [CGRect] = []

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [palette.surfaceTop, palette.surfaceBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(RadialGradient(colors: [palette.accent.opacity(palette.isDark ? 0.07 : 0.025), .clear],
                                     center: .center, startRadius: 0, endRadius: 280))
            Circle()
                .fill(LinearGradient(stops: [
                    .init(color: .white.opacity(palette.isDark ? 0.035 : 0.18), location: 0),
                    .init(color: .white.opacity(0.01), location: 0.35),
                    .init(color: .clear, location: 0.6),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            texture
                .mask {
                    ZStack {
                        Rectangle().fill(.white)
                        ForEach(captionRects.indices, id: \.self) { index in
                            let rect = captionRects[index].insetBy(dx: -10, dy: -5)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.black.opacity(0.92))
                                .frame(width: rect.width, height: rect.height)
                                .blur(radius: 7)
                                .position(x: rect.midX, y: rect.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
                .clipShape(Circle().inset(by: 1))
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: .clear, location: 0.65),
                    .init(color: .black.opacity(palette.isDark ? 0.22 : 0.035), location: 1),
                ], center: .center, startRadius: 0, endRadius: 280))
            Circle().strokeBorder(palette.border, lineWidth: 0.75)
            Circle().inset(by: 1)
                .strokeBorder(LinearGradient(colors: [
                    .white.opacity(palette.isDark ? 0.23 : 0.65), .white.opacity(0.02),
                    palette.accent.opacity(0.12),
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var texture: some View {
        ZStack {
            ZStack {
                InstrumentGrid(spacing: 28)
                    .stroke(palette.grid, lineWidth: 0.75)
                InstrumentGrid(spacing: 112)
                    .stroke(palette.majorGrid, lineWidth: 0.85)
            }
            .mask(RadialGradient(stops: [
                .init(color: .white.opacity(0.45), location: 0),
                .init(color: .white.opacity(0.70), location: 0.45),
                .init(color: .white, location: 1),
            ], center: .center, startRadius: 0, endRadius: 280))
            InstrumentScanlines()
                .stroke(palette.scanline, lineWidth: 0.5)
        }
    }
}

private struct InstrumentScanlines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for row in 0...Int((rect.height / 3).rounded(.up)) {
            let y = rect.minY + CGFloat(row) * 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct InstrumentGrid: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = Int((rect.width / 2 / spacing).rounded(.up))
        let rows = Int((rect.height / 2 / spacing).rounded(.up))
        for column in -columns...columns {
            let x = rect.midX + CGFloat(column) * spacing
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for row in -rows...rows {
            let y = rect.midY + CGFloat(row) * spacing
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
