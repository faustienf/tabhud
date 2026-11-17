#!/usr/bin/env swift
// Rebuilds the CRT icon artwork; Icon Composer supplies the rounded graphite tile.
// Run `swift scripts/draw-icon-layers.swift`, then `scripts/setup.sh install`.
// Transparent 1024×1024 layers: display.png, phosphor-orbit.png, phosphor-command.png.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let center = CGPoint(x: 512, y: 512)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let phosphor = CGColor(red: 0.48, green: 0.88, blue: 0.65, alpha: 1)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Support/AppIcon.icon/Assets", isDirectory: true)

func render(_ name: String, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context)
    let url = outputDirectory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    print("✓ \(url.path)")
}

func stroke(_ path: CGPath, in context: CGContext, color: CGColor, width: CGFloat,
            glow: CGFloat = 0) {
    context.saveGState()
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(color)
    if glow > 0 { context.setShadow(offset: .zero, blur: glow, color: phosphor.copy(alpha: 0.55)) }
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}

func orbit(from start: CGFloat, to end: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addArc(center: center, radius: 332, startAngle: start, endAngle: end, clockwise: false)
    return path
}

/// A continuous Command symbol: a square whose corners turn into four 270° loops.
func commandPath() -> CGPath {
    let half: CGFloat = 60
    let c = half * 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x - half, y: center.y + c))
    let loops: [(CGFloat, CGFloat, CGFloat)] = [
        (-c, -c, 0), (c, -c, .pi / 2), (c, c, .pi), (-c, c, 3 * .pi / 2),
    ]
    for (dx, dy, start) in loops {
        path.addArc(center: CGPoint(x: center.x + dx, y: center.y + dy), radius: half,
                    startAngle: start, endAngle: start + .pi / 2, clockwise: true)
    }
    path.closeSubpath()
    return path
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

try render("display.png") { context in
    // Larger squares survive downscaling; a faded center keeps the glyph uncluttered.
    for index in -6...6 {
        let coordinate = CGFloat(512 + index * 88)
        let major = index.isMultiple(of: 2)
        context.setStrokeColor(phosphor.copy(alpha: major ? 0.20 : 0.10)!)
        context.setLineWidth(major ? 2.5 : 1.5)
        context.move(to: CGPoint(x: coordinate, y: 0))
        context.addLine(to: CGPoint(x: coordinate, y: 1024))
        context.move(to: CGPoint(x: 0, y: coordinate))
        context.addLine(to: CGPoint(x: 1024, y: coordinate))
        context.strokePath()
    }
    context.setStrokeColor(phosphor.copy(alpha: 0.025)!)
    context.setLineWidth(1)
    for y in stride(from: 0, through: size, by: 8) {
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: size, y: y))
    }
    context.strokePath()
    context.saveGState()
    context.setBlendMode(.destinationIn)
    let mask = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0.85), CGColor(gray: 1, alpha: 0.3),
    ] as CFArray, locations: [0, 0.65, 1])!
    context.drawRadialGradient(mask, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: 650, options: [.drawsAfterEndLocation])
    context.restoreGState()
    let sheen = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(gray: 1, alpha: 0.075), CGColor(gray: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sheen, start: CGPoint(x: 100, y: 1024),
                               end: CGPoint(x: 800, y: 380), options: [.drawsBeforeStartLocation])
}

try render("phosphor-orbit.png") { context in
    stroke(orbit(from: 0, to: 2 * .pi), in: context,
           color: CGColor(red: 0.33, green: 0.57, blue: 0.42, alpha: 0.55), width: 13)
    let trace = orbit(from: .pi / 12, to: 5 * .pi / 12)
    stroke(trace, in: context, color: phosphor.copy(alpha: 0.24)!, width: 27, glow: 24)
    stroke(trace, in: context, color: phosphor, width: 20, glow: 9)
    stroke(trace, in: context, color: CGColor(red: 0.73, green: 1, blue: 0.84, alpha: 0.9), width: 5)
}

try render("phosphor-command.png") { context in
    let glyph = commandPath()
    stroke(glyph, in: context, color: phosphor.copy(alpha: 0.2)!, width: 35, glow: 26)
    stroke(glyph, in: context, color: CGColor(red: 0.65, green: 0.95, blue: 0.78, alpha: 1), width: 28, glow: 8)
}
