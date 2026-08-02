#!/usr/bin/env swift
//
// Draws MultiClock's app icon and writes an .iconset directory.
//
// The icon is drawn programmatically rather than shipped as a binary asset so it
// stays diffable and every size is rendered natively instead of downsampled from
// one master — small sizes drop detail deliberately (see `drawIcon`).
//
//   swift Tools/GenerateIcon.swift Resources/AppIcon.iconset
//   iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
//
import AppKit
import CoreGraphics
import Foundation

// MARK: - Geometry

/// macOS icons don't fill their canvas: the rounded square occupies 824 of 1024
/// points, and the surrounding margin is where the system draws the drop shadow.
let squircleRatio: CGFloat = 824.0 / 1024.0
let cornerRatio: CGFloat = 185.4 / 824.0

func drawIcon(size s: CGFloat, into ctx: CGContext) {
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.setShouldAntialias(true)

    // MARK: Background squircle

    let plateSide = s * squircleRatio
    let plateOrigin = (s - plateSide) / 2
    let plateRect = CGRect(x: plateOrigin, y: plateOrigin, width: plateSide, height: plateSide)
    let plate = CGPath(
        roundedRect: plateRect,
        cornerWidth: plateSide * cornerRatio,
        cornerHeight: plateSide * cornerRatio,
        transform: nil
    )

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()

    // Twilight gradient: the "same instant, different sky" idea behind time zones.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.42, green: 0.51, blue: 0.98, alpha: 1.0),
            CGColor(red: 0.24, green: 0.29, blue: 0.80, alpha: 1.0),
            CGColor(red: 0.10, green: 0.13, blue: 0.44, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: plateRect.minX, y: plateRect.maxY),
        end: CGPoint(x: plateRect.maxX, y: plateRect.minY),
        options: []
    )

    // Soft top-edge sheen, the way macOS plates catch light.
    let sheen = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: plateRect.midX, y: plateRect.maxY),
        end: CGPoint(x: plateRect.midX, y: plateRect.midY),
        options: []
    )
    ctx.restoreGState()

    // MARK: Primary clock

    // The face sits off-centre to leave room for the secondary ring. Below 32pt that
    // ring isn't drawn, so the offset would just waste pixels at the size with the
    // fewest to spare — recentre and grow instead.
    let hasSecondary = s >= 32
    let center = hasSecondary
        ? CGPoint(x: s * 0.545, y: s * 0.445)
        : CGPoint(x: s * 0.5, y: s * 0.5)
    let radius = s * (hasSecondary ? 0.245 : 0.290)

    /// The primary face plus a small margin. The secondary ring is clipped against
    /// this so the two read as objects at different depths.
    let haloRadius = radius * 1.13
    let halo = CGRect(
        x: center.x - haloRadius,
        y: center.y - haloRadius,
        width: haloRadius * 2,
        height: haloRadius * 2
    )

    // MARK: Secondary clock

    // The "multi" in MultiClock: a second face peeking out behind the first.
    // Below 32pt there aren't enough pixels for it to read as anything but noise,
    // so it's dropped and the primary face is what survives.
    if hasSecondary {
        let secondaryCenter = CGPoint(x: s * 0.345, y: s * 0.655)
        let secondaryRadius = s * 0.150

        // Even-odd clip (whole canvas XOR halo) masks the ring where it would run
        // behind the primary face. Drawing it and then repainting the background
        // over the overlap instead would leave an antialiased seam.
        ctx.saveGState()
        let mask = CGMutablePath()
        mask.addRect(CGRect(x: 0, y: 0, width: s, height: s))
        mask.addEllipse(in: halo)
        ctx.addPath(mask)
        ctx.clip(using: .evenOdd)

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
        ctx.setLineWidth(s * 0.038)
        ctx.strokeEllipse(
            in: CGRect(
                x: secondaryCenter.x - secondaryRadius,
                y: secondaryCenter.y - secondaryRadius,
                width: secondaryRadius * 2,
                height: secondaryRadius * 2
            )
        )
        ctx.restoreGState()
    }

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.setLineWidth(s * 0.052)
    ctx.strokeEllipse(
        in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    )

    // Hour ticks only survive at sizes with pixels to spare; at 32pt and below they
    // smear into a grey ring and make the face muddier, not richer.
    if s >= 128 {
        ctx.setLineCap(.round)
        ctx.setLineWidth(s * 0.020)
        for hour in 0..<12 {
            let angle = CGFloat(hour) * .pi / 6
            let outer = radius * 0.80
            let inner = radius * (hour % 3 == 0 ? 0.60 : 0.70)
            ctx.move(to: CGPoint(
                x: center.x + sin(angle) * inner,
                y: center.y + cos(angle) * inner
            ))
            ctx.addLine(to: CGPoint(
                x: center.x + sin(angle) * outer,
                y: center.y + cos(angle) * outer
            ))
        }
        ctx.strokePath()
    }

    // Hands at 10:09 — the conventional display angle, and it keeps both hands
    // clear of the secondary ring behind the upper left.
    ctx.setLineCap(.round)

    let hourAngle: CGFloat = 10.15 / 12 * 2 * .pi
    ctx.setLineWidth(s * 0.046)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(
        x: center.x + sin(hourAngle) * radius * 0.46,
        y: center.y + cos(hourAngle) * radius * 0.46
    ))
    ctx.strokePath()

    let minuteAngle: CGFloat = 9.0 / 60 * 2 * .pi
    ctx.setLineWidth(s * 0.038)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(
        x: center.x + sin(minuteAngle) * radius * 0.68,
        y: center.y + cos(minuteAngle) * radius * 0.68
    ))
    ctx.strokePath()

    if s >= 64 {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
        let dot = s * 0.026
        ctx.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
    }
}

// MARK: - Rendering

func renderPNG(size: Int, to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.contextFailed(size)
    }

    drawIcon(size: CGFloat(size), into: ctx)

    guard let image = ctx.makeImage() else { throw IconError.imageFailed(size) }
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) else {
        throw IconError.writeFailed(url)
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.writeFailed(url) }
}

enum IconError: Error, CustomStringConvertible {
    case contextFailed(Int)
    case imageFailed(Int)
    case writeFailed(URL)

    var description: String {
        switch self {
        case .contextFailed(let size): "Could not create a \(size)pt bitmap context"
        case .imageFailed(let size): "Could not render the \(size)pt image"
        case .writeFailed(let url): "Could not write \(url.path)"
        }
    }
}

// MARK: - Entry point

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)

try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

// The set `iconutil` expects; omitting any of these makes it refuse the folder.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    try renderPNG(size: variant.size, to: outputURL.appendingPathComponent(variant.name))
    print("  rendered \(variant.name) (\(variant.size)px)")
}

print("Wrote \(variants.count) images to \(outputPath)")
