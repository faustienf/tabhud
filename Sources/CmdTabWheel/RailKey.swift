import SwiftUI

/// × or ★ set into the selection rim: a phosphor glyph on the glass, nothing behind it.
/// Pointing at it only changes its color. Clicks never reach SwiftUI here (WheelWindow takes
/// them all): WheelModel hit-tests it.
struct RailKey: View {
    let button: WheelModel.RailButton
    /// A favorite's ★.
    var isLit = false
    var isHovered = false
    /// Busy with a close or quit request: × spins, ★ dims.
    var isBusy = false
    /// Can't do anything here: a × for a window on another desktop.
    var isDimmed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WheelPalette(isDark: colorScheme == .dark)
        let tint = button == .close ? palette.destructive : palette.accent
        ZStack {
            if isBusy && button == .close {
                RailKeySpinner(tint: palette.accent)
            } else {
                glyph
                    .foregroundStyle(isHovered || isLit ? tint : palette.ink.opacity(0.72))
                    .opacity(isBusy || isDimmed ? 0.3 : 1)
            }
        }
        .frame(width: WheelLayout.railKeySize, height: WheelLayout.railKeySize)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isLit)
    }

    @ViewBuilder
    private var glyph: some View {
        switch button {
        case .close:
            Image(systemName: "xmark")
                .font(.system(size: 10.5, weight: .semibold))
        case .favorite:
            FavoriteGlyph(isFilled: isLit)
                .frame(width: 12.5, height: 12.5)
        }
    }
}

/// A short phosphor arc going round in place of × while a window closes or an app quits.
private struct RailKeySpinner: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            // Keeps moving with Reduce Motion, only more slowly: it's the only sign of progress.
            let period = reduceMotion ? 2.0 : 0.9
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .background(Circle().stroke(tint.opacity(0.18), lineWidth: 1.6))
                .rotationEffect(.radians(turn * 2 * .pi))
                .frame(width: 11, height: 11)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Closing…")
    }
}
