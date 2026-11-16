import SwiftUI

/// Pulse the whole icon so the pointer can't hide a small activity mark.
/// Only opacity changes, including when Reduce Motion is enabled.
struct QuittingAppAppearance: ViewModifier {
    let isQuitting: Bool

    func body(content: Content) -> some View {
        if isQuitting {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                content.opacity(Self.opacity(at: context.date))
            }
        } else {
            content
        }
    }

    static func opacity(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
        return 0.42 + 0.30 * (1 - cos(phase * 2 * .pi)) / 2
    }
}
