// Draws the background of the DMG window; scripts/setup.sh package runs it:
//
//   swift scripts/draw-dmg-background.swift <output.tiff>
//
// The wheel's light glass with its grid, "drag it into Applications" and how to get past
// Gatekeeper. Light on purpose: Finder draws the icon labels black on a picture background,
// in dark mode too. One TIFF with 1x and 2x pictures, for Retina screens.
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/draw-dmg-background.swift <output.tiff>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

// The window's content, in points (y down, like Finder). scripts/dmg-settings.py puts the
// icons' centers here. The window is 432 tall with its title bar, so 400 of content on macOS 26
// (32 for the title bar) and 404 before (28); the picture runs on below that, so no strip of
// plain window shows under it.
let size = CGSize(width: 640, height: 440)
let appCenter = CGPoint(x: 160, y: 190)
let applicationsCenter = CGPoint(x: 480, y: 190)

// WheelPalette, light.
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let ink = rgb(0.12, 0.18, 0.15)
let secondaryInk = rgb(0.33, 0.43, 0.38)
let accent = rgb(0.08, 0.42, 0.26)
let surfaceTop = rgb(0.97, 0.98, 0.975)
let surfaceBottom = rgb(0.90, 0.93, 0.92)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(NSColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map(\.0.cgColor) as CFArray, locations: stops.map(\.1))!
}

func mono(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    .monospacedSystemFont(ofSize: size, weight: weight)
}

func text(_ parts: [(String, NSFont, NSColor)]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (string, font, color) in parts {
        result.append(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
    }
    return result
}

/// Draws `string` centered horizontally, its middle at `y`.
func drawCentered(_ string: NSAttributedString, y: CGFloat) {
    let bounds = string.size()
    string.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: y - bounds.height / 2))
}

func strokeGlowing(_ path: CGPath, in cg: CGContext, width: CGFloat) {
    cg.saveGState()
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setShadow(offset: .zero, blur: 7, color: accent.withAlphaComponent(0.45).cgColor)
    cg.addPath(path)
    cg.setStrokeColor(accent.cgColor)
    cg.setLineWidth(width)
    cg.strokePath()
    cg.restoreGState()
}

func draw(in cg: CGContext) {
    let center = CGPoint(x: size.width / 2, y: 200) // of the 400 points that always show

    // Glass.
    cg.drawLinearGradient(gradient([(surfaceTop, 0), (surfaceBottom, 1)]),
                          start: .zero, end: CGPoint(x: size.width * 0.3, y: 400),
                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.drawRadialGradient(gradient([(accent.withAlphaComponent(0.05), 0), (accent.withAlphaComponent(0), 1)]),
                          startCenter: center, startRadius: 0, endCenter: center, endRadius: 340, options: [])

    // Grid and scanlines, as on the wheel.
    for (spacing, alpha, width) in [(28.0, 0.07, 0.75), (112.0, 0.12, 0.85)] as [(CGFloat, CGFloat, CGFloat)] {
        let grid = CGMutablePath()
        var x = center.x.truncatingRemainder(dividingBy: spacing)
        while x <= size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y = center.y.truncatingRemainder(dividingBy: spacing)
        while y <= size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        cg.addPath(grid)
        cg.setStrokeColor(accent.withAlphaComponent(alpha).cgColor)
        cg.setLineWidth(width)
        cg.strokePath()
    }
    let scanlines = CGMutablePath()
    for row in stride(from: 0, through: size.height, by: 3) {
        scanlines.move(to: CGPoint(x: 0, y: row))
        scanlines.addLine(to: CGPoint(x: size.width, y: row))
    }
    cg.addPath(scanlines)
    cg.setStrokeColor(accent.withAlphaComponent(0.025).cgColor)
    cg.setLineWidth(0.5)
    cg.strokePath()
    // Calmer where the title and icons are.
    cg.drawRadialGradient(gradient([(surfaceTop.withAlphaComponent(0.55), 0), (surfaceTop.withAlphaComponent(0), 1)]),
                          startCenter: center, startRadius: 0, endCenter: center, endRadius: 260, options: [])
    // Vignette.
    cg.drawRadialGradient(gradient([(.clear, 0.62), (.black.withAlphaComponent(0.045), 1)]),
                          startCenter: center, startRadius: 0, endCenter: center,
                          endRadius: hypot(size.width, 400) / 2, options: [.drawsAfterEndLocation])

    // Title.
    drawCentered(text([
        ("Drag ", mono(19, .semibold), ink),
        ("⌘", mono(19, .semibold), accent),
        ("Tab HUD into Applications", mono(19, .semibold), ink),
    ]), y: 62)

    // Arrow from the app to Applications.
    let start = CGPoint(x: appCenter.x + 92, y: appCenter.y - 4)
    let end = CGPoint(x: applicationsCenter.x - 92, y: applicationsCenter.y - 4)
    let control = CGPoint(x: (start.x + end.x) / 2, y: start.y - 44)
    let arc = CGMutablePath()
    arc.move(to: start)
    arc.addQuadCurve(to: end, control: control)
    strokeGlowing(arc, in: cg, width: 3)
    let direction = atan2(end.y - control.y, end.x - control.x)
    func barb(_ side: CGFloat) -> CGPoint {
        CGPoint(x: end.x - 15 * cos(direction + side), y: end.y - 15 * sin(direction + side))
    }
    let head = CGMutablePath()
    head.move(to: barb(0.5))
    head.addLine(to: end)
    head.addLine(to: barb(-0.5))
    strokeGlowing(head, in: cg, width: 3)

    // Gatekeeper, under the icons' labels.
    let first = text([("The first time, macOS won't open it: it isn't notarized.", mono(11, .regular), secondaryInk)])
    let second = text([
        ("System Settings → Privacy & Security → ", mono(11, .medium), ink),
        ("Open Anyway", mono(11, .semibold), accent),
    ])
    let panelWidth = max(first.size().width, second.size().width) + 40
    let panel = CGRect(x: (size.width - panelWidth) / 2, y: 312, width: panelWidth, height: 54)
    let plate = CGPath(roundedRect: panel, cornerWidth: 10, cornerHeight: 10, transform: nil)
    cg.addPath(plate)
    cg.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
    cg.fillPath()
    cg.addPath(plate)
    cg.setStrokeColor(accent.withAlphaComponent(0.28).cgColor)
    cg.setLineWidth(0.75)
    cg.strokePath()
    drawCentered(first, y: panel.midY - 9)
    drawCentered(second, y: panel.midY + 10)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let width = Int(size.width * scale), height = Int(size.height * scale)
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Points, y down.
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw(in: cg)
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
    rep.size = size // 144 dpi for the 2x one
    return rep
}

let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)],
                                                            using: .lzw, factor: 0)!
try tiff.write(to: output)
