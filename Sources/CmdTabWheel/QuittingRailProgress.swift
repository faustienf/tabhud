import SwiftUI

/// An indeterminate activity band inside the existing rail, without changing its size.
struct QuittingRailProgress: View {
    let angle: Double
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = WheelPalette(isDark: colorScheme == .dark).accent
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            // A short activity cue keeps moving with Reduce Motion, only more slowly.
            let period = reduceMotion ? 1.3 : 0.9
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            QuittingRailBand(angle: angle, radius: radius, phase: phase, tint: accent)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Closing…")
    }
}

struct QuittingRailBand: View {
    let angle: Double
    let radius: CGFloat
    let phase: Double
    let tint: Color

    var body: some View {
        let arc = ActionRailArc(angle: angle, radius: radius,
                                start: -WheelLayout.actionRailHalfAngle,
                                end: WheelLayout.actionRailHalfAngle)
        let start = phase * 1.35 - 0.35
        ZStack {
            arc.stroke(tint.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            arc.trim(from: max(0, start), to: min(1, start + 0.35))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: tint.opacity(0.35), radius: 2)
        }
    }
}
