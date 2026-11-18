import SwiftUI

/// A graphite CRT surface with green phosphor lettering and highlights.
struct WheelPalette {
    let isDark: Bool

    var ink: Color {
        isDark ? Color(red: 0.76, green: 0.91, blue: 0.82) : Color(red: 0.12, green: 0.18, blue: 0.15)
    }

    var secondaryInk: Color {
        isDark ? Color(red: 0.55, green: 0.70, blue: 0.61) : Color(red: 0.33, green: 0.43, blue: 0.38)
    }

    var accent: Color {
        isDark ? Color(red: 0.48, green: 0.88, blue: 0.65) : Color(red: 0.08, green: 0.42, blue: 0.26)
    }

    /// A restrained warm hover cue distinguishes closing from starring a window.
    var destructive: Color {
        isDark ? Color(red: 1, green: 0.59, blue: 0.53) : Color(red: 0.68, green: 0.22, blue: 0.18)
    }

    var surfaceTop: Color {
        isDark ? Color(red: 0.09, green: 0.12, blue: 0.11).opacity(0.34)
               : Color(red: 0.97, green: 0.98, blue: 0.975).opacity(0.22)
    }

    var surfaceBottom: Color {
        isDark ? Color(red: 0.05, green: 0.07, blue: 0.06).opacity(0.46)
               : Color(red: 0.90, green: 0.93, blue: 0.92).opacity(0.34)
    }

    var grid: Color { accent.opacity(isDark ? 0.15 : 0.09) }
    var majorGrid: Color { accent.opacity(isDark ? 0.25 : 0.16) }
    var scanline: Color { accent.opacity(isDark ? 0.035 : 0.025) }
    var border: Color { ink.opacity(isDark ? 0.24 : 0.14) }

    func selectionFill(reach: CGFloat) -> Color {
        ink.opacity(isDark ? 0.06 + 0.20 * Double(reach) : 0.06 + 0.14 * Double(reach))
    }

    func selectionAccent(reach: CGFloat) -> Color {
        accent.opacity(isDark ? 0.08 + 0.23 * Double(reach) : 0.04 + 0.16 * Double(reach))
    }

    var separator: Color { ink.opacity(0.12) }

    var actionRailSurface: Color {
        isDark ? Color(red: 0.14, green: 0.19, blue: 0.16).opacity(0.98) : Color(white: 0.98).opacity(0.98)
    }

    var markSurface: Color {
        isDark ? Color(red: 0.19, green: 0.25, blue: 0.215) : actionRailSurface
    }

    var previewShadow: Double { isDark ? 0.26 : 0.12 }
}
