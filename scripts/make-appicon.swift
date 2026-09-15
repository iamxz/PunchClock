import AppKit

// 生成 Daka 应用图标（.iconset），供 iconutil 转 .icns。
// 用法: swift scripts/make-appicon.swift Resources/AppIcon.iconset

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func render(px: Int) -> Data {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let margin = size * 0.08
    let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let radius = rect.width * 0.2237
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.29, green: 0.52, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.13, green: 0.22, blue: 0.66, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -90)

    let center = CGPoint(x: size / 2, y: size / 2)
    let faceRadius = rect.width * 0.30

    NSColor.white.setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - faceRadius, y: center.y - faceRadius,
                                width: faceRadius * 2, height: faceRadius * 2)).fill()

    let ink = NSColor(srgbRed: 0.13, green: 0.22, blue: 0.66, alpha: 1)
    ink.setStroke()

    let hourHand = NSBezierPath()
    hourHand.lineWidth = max(1, size * 0.021)
    hourHand.lineCapStyle = .round
    hourHand.move(to: center)
    hourHand.line(to: CGPoint(x: center.x, y: center.y + faceRadius * 0.60))
    hourHand.stroke()

    let minuteHand = NSBezierPath()
    minuteHand.lineWidth = max(1, size * 0.021)
    minuteHand.lineCapStyle = .round
    minuteHand.move(to: center)
    minuteHand.line(to: CGPoint(x: center.x + faceRadius * 0.40, y: center.y - faceRadius * 0.12))
    minuteHand.stroke()

    let badgeRadius = rect.width * 0.155
    let badgeCenter = CGPoint(x: rect.maxX - badgeRadius * 1.02, y: rect.minY + badgeRadius * 1.02)
    NSColor.systemGreen.setFill()
    NSBezierPath(ovalIn: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                                width: badgeRadius * 2, height: badgeRadius * 2)).fill()

    NSColor.white.setStroke()
    let check = NSBezierPath()
    check.lineWidth = max(1, size * 0.023)
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: CGPoint(x: badgeCenter.x - badgeRadius * 0.42, y: badgeCenter.y + badgeRadius * 0.02))
    check.line(to: CGPoint(x: badgeCenter.x - badgeRadius * 0.08, y: badgeCenter.y - badgeRadius * 0.34))
    check.line(to: CGPoint(x: badgeCenter.x + badgeRadius * 0.45, y: badgeCenter.y + badgeRadius * 0.38))
    check.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return Data()
    }
    return png
}

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for spec in sizes {
    let data = render(px: spec.px)
    do {
        try data.write(to: outDir.appendingPathComponent(spec.name))
    } catch {
        FileHandle.standardError.write(Data("failed to write \(spec.name): \(error)\n".utf8))
        exit(1)
    }
}
print("wrote \(sizes.count) images to \(outDir.path)")
