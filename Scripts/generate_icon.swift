#!/usr/bin/env swift
// Renders HZLAPaste's app icon as pure vector shapes (no traced/copied artwork,
// no third-party assets): a dark medallion, a low-poly wolf emblem, and a clip
// badge for "clipboard". Re-run any time to tweak: `swift Scripts/generate_icon.swift`.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cx = CGFloat(size) / 2
let cy = CGFloat(size) / 2

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create bitmap context") }

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: cx + dx, y: cy + dy) }
func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

// MARK: - Medallion base
let medallionRadius: CGFloat = 460
let medallionRect = CGRect(x: cx - medallionRadius, y: cy - medallionRadius,
                            width: medallionRadius * 2, height: medallionRadius * 2)

ctx.saveGState()
ctx.addEllipse(in: medallionRect)
ctx.clip()
let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [rgba(0.17, 0.17, 0.20), rgba(0.03, 0.03, 0.04)] as CFArray,
                             locations: [0, 1])!
ctx.drawRadialGradient(bgGradient, startCenter: CGPoint(x: cx, y: cy + 90), startRadius: 20,
                        endCenter: CGPoint(x: cx, y: cy), endRadius: medallionRadius,
                        options: [.drawsAfterEndLocation])
ctx.restoreGState()

// Silver rim (gradient-filled ring via stroked-path clip)
ctx.saveGState()
ctx.setLineWidth(28)
ctx.addEllipse(in: medallionRect.insetBy(dx: 14, dy: 14))
ctx.replacePathWithStrokedPath()
ctx.clip()
let rimGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [rgba(0.88, 0.89, 0.92), rgba(0.40, 0.41, 0.45)] as CFArray,
                              locations: [0, 1])!
ctx.drawLinearGradient(rimGradient, start: CGPoint(x: cx, y: cy + medallionRadius),
                        end: CGPoint(x: cx, y: cy - medallionRadius), options: [])
ctx.restoreGState()

// MARK: - Low-poly wolf head (original geometric silhouette)
let wolfPath = polygon([
    point(-165, 195), point(-195, 40), point(-72, 62), point(0, 95),
    point(72, 62), point(195, 40), point(165, 195),
    point(140, -35), point(58, -165), point(0, -230),
    point(-58, -165), point(-140, -35)
])

ctx.saveGState()
ctx.addPath(wolfPath)
ctx.clip()
let furGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [rgba(0.94, 0.94, 0.96), rgba(0.58, 0.59, 0.63)] as CFArray,
                              locations: [0, 1])!
ctx.drawLinearGradient(furGradient, start: point(0, 230), end: point(0, -230), options: [])
ctx.restoreGState()

ctx.setStrokeColor(rgba(0.13, 0.13, 0.15))
ctx.setLineWidth(6)
ctx.addPath(wolfPath)
ctx.strokePath()

// Eyes (angular, fierce)
ctx.setFillColor(rgba(0.05, 0.05, 0.06))
ctx.addPath(polygon([point(-58, -15), point(-16, -6), point(-46, -42)]))
ctx.fillPath()
ctx.addPath(polygon([point(58, -15), point(16, -6), point(46, -42)]))
ctx.fillPath()

// Nose
ctx.addPath(polygon([point(0, -195), point(-22, -160), point(22, -160)]))
ctx.fillPath()

// Center face crease
ctx.setStrokeColor(rgba(0.30, 0.30, 0.33))
ctx.setLineWidth(4)
ctx.move(to: point(0, 95))
ctx.addLine(to: point(0, -160))
ctx.strokePath()

// MARK: - Clip badge (signals "clipboard")
let clipRect = CGRect(x: cx - 80, y: cy + medallionRadius - 70, width: 160, height: 90)
let clipPath = CGPath(roundedRect: clipRect, cornerWidth: 18, cornerHeight: 18, transform: nil)
let tabRect = CGRect(x: cx - 34, y: clipRect.maxY - 14, width: 68, height: 40)
let tabPath = CGPath(roundedRect: tabRect, cornerWidth: 10, cornerHeight: 10, transform: nil)

ctx.saveGState()
ctx.addPath(clipPath)
ctx.addPath(tabPath)
ctx.clip()
let goldGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [rgba(0.85, 0.72, 0.40), rgba(0.55, 0.43, 0.18)] as CFArray,
                               locations: [0, 1])!
ctx.drawLinearGradient(goldGradient, start: CGPoint(x: cx, y: clipRect.maxY + 40),
                        end: CGPoint(x: cx, y: clipRect.minY), options: [])
ctx.restoreGState()

ctx.setStrokeColor(rgba(0.25, 0.20, 0.10))
ctx.setLineWidth(4)
ctx.addPath(clipPath)
ctx.strokePath()
ctx.addPath(tabPath)
ctx.strokePath()

// MARK: - Export
guard let cgImage = ctx.makeImage() else { fatalError("could not render image") }
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let outputURL = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not create image destination")
}
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write PNG") }
print("Wrote \(outputURL.path)")
