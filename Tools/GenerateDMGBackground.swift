#!/usr/bin/env swift
//
// Draws the installer window background for the DMG.
//
// Rendered at 1x and 2x so `tiffutil` can pack both into a multi-resolution TIFF —
// Finder maps the background 1:1 to points, so a plain 2x PNG would produce a window
// twice the intended size instead of a crisp one.
//
//   swift Tools/GenerateDMGBackground.swift <output-dir>
//
import AppKit
import Foundation

// Must match the icon positions and window size used in package.sh.
let width: CGFloat = 660
let height: CGFloat = 420
let appIconCenter = CGPoint(x: 170, y: 250)      // from bottom-left
let applicationsCenter = CGPoint(x: 490, y: 250)

func draw(scale: CGFloat, to url: URL) throws {
    let pixelWidth = Int(width * scale)
    let pixelHeight = Int(height * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw Failure.rep }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { throw Failure.context }
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: scale, y: scale)

    let cg = ctx.cgContext

    // Background: a soft vertical wash picking up the app icon's blue, kept light so
    // Finder's icon labels stay readable in both appearances.
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.96, green: 0.97, blue: 1.00, alpha: 1),
            CGColor(red: 0.90, green: 0.92, blue: 0.98, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    cg.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // Arrow from the app toward the Applications folder.
    let arrowY = appIconCenter.y
    let startX = appIconCenter.x + 96
    let endX = applicationsCenter.x - 96
    let headLength: CGFloat = 22
    let arrowColor = CGColor(red: 0.36, green: 0.42, blue: 0.75, alpha: 0.85)

    cg.setStrokeColor(arrowColor)
    cg.setLineWidth(5)
    cg.setLineCap(.round)
    cg.move(to: CGPoint(x: startX, y: arrowY))
    cg.addLine(to: CGPoint(x: endX - headLength + 4, y: arrowY))
    cg.strokePath()

    cg.setFillColor(arrowColor)
    cg.move(to: CGPoint(x: endX, y: arrowY))
    cg.addLine(to: CGPoint(x: endX - headLength, y: arrowY + 13))
    cg.addLine(to: CGPoint(x: endX - headLength, y: arrowY - 13))
    cg.closePath()
    cg.fillPath()

    // Instruction line, centred under the arrow.
    let instruction = "Drag MultiClock into your Applications folder"
    let instructionAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.24, green: 0.28, blue: 0.45, alpha: 1),
    ]
    let instructionSize = instruction.size(withAttributes: instructionAttrs)
    instruction.draw(
        at: NSPoint(x: (width - instructionSize.width) / 2, y: 96),
        withAttributes: instructionAttrs
    )

    let title = "MultiClock"
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.38, alpha: 1),
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    title.draw(
        at: NSPoint(x: (width - titleSize.width) / 2, y: height - 62),
        withAttributes: titleAttrs
    )

    guard let data = rep.representation(using: .png, properties: [:]) else { throw Failure.encode }
    try data.write(to: url)
}

enum Failure: Error { case rep, context, encode }

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

try draw(scale: 1, to: outputDir.appendingPathComponent("background.png"))
try draw(scale: 2, to: outputDir.appendingPathComponent("background@2x.png"))
print("wrote background.png and background@2x.png to \(outputDir.path)")
