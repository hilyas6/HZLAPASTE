import AppKit

/// Draws the same low-poly wolf silhouette used in the Dock icon (see
/// Scripts/generate_icon.swift) as a small template image for the menu bar.
/// Menu bar icons are conventionally monochrome/template-style, so this reuses
/// the emblem's shape rather than embedding the full-color medallion artwork —
/// no bundled resource file needed, just the same coordinates redrawn small.
enum WolfIcon {
    private static let silhouette: [CGPoint] = [
        CGPoint(x: -165, y: 195), CGPoint(x: -195, y: 40), CGPoint(x: -72, y: 62), CGPoint(x: 0, y: 95),
        CGPoint(x: 72, y: 62), CGPoint(x: 195, y: 40), CGPoint(x: 165, y: 195),
        CGPoint(x: 140, y: -35), CGPoint(x: 58, y: -165), CGPoint(x: 0, y: -230),
        CGPoint(x: -58, y: -165), CGPoint(x: -140, y: -35)
    ]

    static func menuBarImage(pointSize: CGFloat = 18) -> NSImage {
        let minX = silhouette.map(\.x).min()!, maxX = silhouette.map(\.x).max()!
        let minY = silhouette.map(\.y).min()!, maxY = silhouette.map(\.y).max()!
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        let usable = pointSize * 0.72 // leaves margin so it doesn't touch the menu bar edges
        let scale = usable / max(maxX - minX, maxY - minY)

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let points = silhouette.map {
                NSPoint(x: rect.midX + ($0.x - midX) * scale, y: rect.midY + ($0.y - midY) * scale)
            }
            let path = NSBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach { path.line(to: $0) }
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
