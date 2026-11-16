import SwiftUI

/// "Started by chrome-devtools-mcp" above the preview.
struct LauncherBadge: View {
    let name: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WheelPalette(isDark: colorScheme == .dark)
        HStack(spacing: 6) {
            LauncherMark(size: 17)
            Text("Started by")
                .foregroundStyle(palette.secondaryInk)
                .fixedSize()
            Text(name)
                .fontWeight(.medium)
                .foregroundStyle(palette.ink.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Started by \(name)")
    }
}

/// A small mark on the corner of the app icon, readable on the ring without selecting it.
struct LauncherMark: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WheelPalette(isDark: colorScheme == .dark)
        let plate = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        LauncherGlyph()
            .stroke(palette.accent, style: StrokeStyle(lineWidth: max(1.1, size * 0.075),
                                                      lineCap: .round, lineJoin: .round))
            .padding(size * 0.20)
            .frame(width: size, height: size)
            .background(plate.fill(palette.markSurface))
            .overlay(plate.strokeBorder(palette.ink.opacity(palette.isDark ? 0.20 : 0.12), lineWidth: 0.65))
            .shadow(color: .black.opacity(palette.previewShadow), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// A vector command prompt: this copy was started by another program.
private struct LauncherGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.78))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.78))
        return path
    }
}
