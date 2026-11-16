import AppKit

/// A native sibling behind the SwiftUI host, so WindowServer can sample the desktop directly.
final class WheelGlassMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        state = .active
        appearance = nil // inherit the selected app theme, including Follow System
        updateMaterial()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMaterial()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    private func updateMaterial() {
        material = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .hudWindow : .sidebar
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, maskImage?.size != bounds.size else { return }
        maskImage = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.black.setFill()
            // Keep the blur mask opaque: fading it mixes sharp desktop text back in.
            // Transparency and the radial tint belong in the foreground glass treatment.
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
