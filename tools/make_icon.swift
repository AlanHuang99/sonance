#!/usr/bin/env swift
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.dropFirst().first ?? "./AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let masterSize: CGFloat = 1024

func render(pixels: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsCtx
    let cg = nsCtx.cgContext

    let s = pixels
    cg.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Apple macOS template: body is 824/1024 (~80.5%) of canvas, leaving room for shadow.
    let bodyInset = s * (100.0 / 1024.0)
    let bodySize = s - bodyInset * 2
    let bodyRect = CGRect(x: bodyInset, y: bodyInset, width: bodySize, height: bodySize)
    let cornerRadius = bodySize * 0.2237  // Apple squircle approximation

    // Subtle drop shadow under the body.
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -bodySize * 0.010),
        blur: bodySize * 0.035,
        color: NSColor(white: 0, alpha: 0.18).cgColor
    )
    cg.setFillColor(NSColor.black.cgColor)
    cg.addPath(CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    cg.fillPath()
    cg.restoreGState()

    // Clip to squircle, then paint warm parchment gradient.
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    cg.clip()

    let top = NSColor(red: 0.957, green: 0.929, blue: 0.878, alpha: 1.0).cgColor    // #F4EDE0
    let bottom = NSColor(red: 0.918, green: 0.875, blue: 0.788, alpha: 1.0).cgColor // #EADFC9
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    )!
    cg.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: bodyRect.maxY),
        end: CGPoint(x: 0, y: bodyRect.minY),
        options: []
    )

    // Glyph: tapered sound wave in dark espresso, 2.5 periods, edge-to-edge.
    let glyphRect = bodyRect.insetBy(dx: bodySize * 0.10, dy: bodySize * 0.32)
    let strokeWidth = bodySize * 0.055
    let cy = glyphRect.midY
    let maxAmplitude = glyphRect.height * 0.45
    let periods = 3.0

    let path = CGMutablePath()
    let steps = 480
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        let envelope = sin(t * .pi)  // 0 at edges, 1 at center
        let x = glyphRect.minX + CGFloat(t) * glyphRect.width
        let y = cy + maxAmplitude * CGFloat(envelope) * CGFloat(sin(t * .pi * 2 * periods))
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }

    cg.setLineWidth(strokeWidth)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(NSColor(red: 0.212, green: 0.188, blue: 0.165, alpha: 1.0).cgColor)  // #36302A
    cg.addPath(path)
    cg.strokePath()

    cg.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(path)\n".utf8))
        return
    }
    try? data.write(to: URL(fileURLWithPath: path))
}

struct Variant {
    let pt: Int
    let scale: Int
    var pixels: CGFloat { CGFloat(pt * scale) }
    var filename: String {
        scale == 1 ? "icon_\(pt).png" : "icon_\(pt)@\(scale)x.png"
    }
}

let variants: [Variant] = [
    Variant(pt: 16, scale: 1), Variant(pt: 16, scale: 2),
    Variant(pt: 32, scale: 1), Variant(pt: 32, scale: 2),
    Variant(pt: 128, scale: 1), Variant(pt: 128, scale: 2),
    Variant(pt: 256, scale: 1), Variant(pt: 256, scale: 2),
    Variant(pt: 512, scale: 1), Variant(pt: 512, scale: 2),
]

for v in variants {
    let rep = render(pixels: v.pixels)
    write(rep, to: "\(outDir)/\(v.filename)")
    print("wrote \(v.filename) (\(Int(v.pixels))px)")
}

let contents = """
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16@2x.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32@2x.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128@2x.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512@2x.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote Contents.json")
