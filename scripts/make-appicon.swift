import AppKit

// 生成 Daka 应用图标（.iconset），扁平化风格，供 iconutil 转 .icns。
//
// 用法:
//   swift scripts/make-appicon.swift <输出目录> [变体]
//   swift scripts/make-appicon.swift --sheet <预览图输出路径>   # 对比全部变体
//
// 变体: clock(默认) | check | ring-check

// MARK: - 画布规范（对齐 macOS Big Sur+ 图标网格）

/// 图标内容宽 / 画布宽 = 824 / 1024
let canvasInset: CGFloat = 0.0977
/// 内容圆角半径 / 内容宽 = 185.4 / 824
let cornerRatio: CGFloat = 0.2237

/// 品牌蓝：扁平纯色，不再使用渐变
let brandBlue = NSColor(srgbRed: 0.208, green: 0.475, blue: 0.965, alpha: 1)

enum Variant: String, CaseIterable {
    case bellRing = "bell-ring"
    case bell
    case spark
    case ringCheck = "ring-check"
    case check
    case clock

    var title: String {
        switch self {
        case .bellRing: return "bell-ring  圆环铃铛"
        case .bell: return "bell  铃铛"
        case .spark: return "spark  助手星芒"
        case .ringCheck: return "ring-check  圈中勾"
        case .check: return "check  对勾"
        case .clock: return "clock  时钟"
        }
    }
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

// MARK: - 绘制

/// 小尺寸下细笔画会被抗锯齿吃掉，这里给笔画设一个最小粗细（仅 ≤64px 生效）。
func strokeWidth(base: CGFloat, px: Int, boost: CGFloat) -> CGFloat {
    px <= 64 ? max(base, CGFloat(px) * boost) : base
}

/// 扁平铃铛：实心剪影 + 铃口横杆 + 铃舌，总高 h，水平居中于 center。
/// 轮廓宽 ≈ 0.90h（铃口最宽），比例取自常见通知铃铛图标。
func drawBell(center: CGPoint, height h: CGFloat) {
    let cx = center.x
    let y0 = center.y - h / 2

    let lipHalf = h * 0.45               // 铃口半宽（最宽处）
    let lipH = h * 0.095                 // 铃口厚度
    let lipBottom = y0 + h * 0.14
    let bodyHalf = h * 0.40              // 铃身底部半宽
    let bodyBottom = lipBottom + lipH    // 铃身坐在铃口上
    let domeR = h * 0.22                 // 顶部圆顶半径
    let domeCY = y0 + h - domeR

    // 铃身：左腰下探 → 底边 → 右腰上收 → 圆顶
    let body = NSBezierPath()
    body.move(to: CGPoint(x: cx - domeR, y: domeCY))
    body.curve(to: CGPoint(x: cx - bodyHalf, y: bodyBottom),
               controlPoint1: CGPoint(x: cx - domeR, y: domeCY - (domeCY - bodyBottom) * 0.45),
               controlPoint2: CGPoint(x: cx - bodyHalf, y: bodyBottom + (domeCY - bodyBottom) * 0.34))
    body.line(to: CGPoint(x: cx + bodyHalf, y: bodyBottom))
    body.curve(to: CGPoint(x: cx + domeR, y: domeCY),
               controlPoint1: CGPoint(x: cx + bodyHalf, y: bodyBottom + (domeCY - bodyBottom) * 0.34),
               controlPoint2: CGPoint(x: cx + domeR, y: domeCY - (domeCY - bodyBottom) * 0.45))
    body.appendArc(withCenter: CGPoint(x: cx, y: domeCY), radius: domeR, startAngle: 0, endAngle: 180)
    body.close()
    body.fill()

    // 铃口横杆
    NSBezierPath(roundedRect: CGRect(x: cx - lipHalf, y: lipBottom, width: lipHalf * 2, height: lipH),
                 xRadius: lipH / 2, yRadius: lipH / 2).fill()

    // 铃舌
    let clapperR = h * 0.068
    NSBezierPath(ovalIn: CGRect(x: cx - clapperR, y: y0,
                                width: clapperR * 2, height: clapperR * 2)).fill()
}

/// 扁平四角星芒（助手感），垂直略长于水平。
func drawSpark(center c: CGPoint, size s: CGFloat) {
    let rv = s * 0.50
    let rh = s * 0.46
    let k: CGFloat = 0.20   // 越小越尖锐（0.3 以上会退化成菱形）

    let path = NSBezierPath()
    let points = [CGPoint(x: c.x, y: c.y + rv), CGPoint(x: c.x + rh, y: c.y),
                  CGPoint(x: c.x, y: c.y - rv), CGPoint(x: c.x - rh, y: c.y)]
    path.move(to: points[0])
    for i in 0..<4 {
        let from = points[i]
        let to = points[(i + 1) % 4]
        let control = CGPoint(x: c.x + (from.x - c.x) * k + (to.x - c.x) * k,
                              y: c.y + (from.y - c.y) * k + (to.y - c.y) * k)
        path.curve(to: to, controlPoint: control)
    }
    path.close()
    path.fill()
}

/// 在已就绪的绘图上下文中绘制图标，原点为左下角，坐标范围 px × px。
func drawIcon(px: Int, variant: Variant) {
    let size = CGFloat(px)
    let margin = (size * canvasInset).rounded()
    let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let radius = rect.width * cornerRatio

    // 底色：纯色圆角方块
    brandBlue.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

    let c = CGPoint(x: rect.midX, y: rect.midY)
    NSColor.white.setStroke()

    switch variant {
    case .bellRing:
        // 白色圆环 + 环内铃铛
        let ringR = rect.width * 0.295
        let ring = NSBezierPath(ovalIn: CGRect(x: c.x - ringR, y: c.y - ringR,
                                              width: ringR * 2, height: ringR * 2))
        ring.lineWidth = strokeWidth(base: rect.width * 0.068, px: px, boost: 0.115)
        ring.stroke()

        NSColor.white.setFill()
        drawBell(center: c, height: rect.width * 0.40)

    case .bell:
        // 单只白色铃铛
        NSColor.white.setFill()
        drawBell(center: c, height: rect.width * 0.66)

    case .spark:
        // 白色四角星芒（助手感）
        NSColor.white.setFill()
        drawSpark(center: c, size: rect.width * 0.70)

    case .clock:
        // 白色实心表盘 + 蓝针指向 3:00（时针朝上、分针朝右）
        let faceR = rect.width * 0.295
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: c.x - faceR, y: c.y - faceR,
                                   width: faceR * 2, height: faceR * 2)).fill()

        let hands = NSBezierPath()
        hands.lineWidth = strokeWidth(base: rect.width * 0.058, px: px, boost: 0.085)
        hands.lineCapStyle = .round
        hands.move(to: c)
        hands.line(to: CGPoint(x: c.x, y: c.y + faceR * 0.55))
        hands.move(to: c)
        hands.line(to: CGPoint(x: c.x + faceR * 0.63, y: c.y))
        brandBlue.setStroke()
        hands.stroke()

    case .check:
        // 单个白色对勾
        let w = rect.width * 0.50
        let h = rect.height * 0.34
        let path = NSBezierPath()
        path.lineWidth = strokeWidth(base: rect.width * 0.115, px: px, boost: 0.17)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: CGPoint(x: c.x - w / 2, y: c.y + h * 0.05))
        path.line(to: CGPoint(x: c.x - w * 0.10, y: c.y - h * 0.55))
        path.line(to: CGPoint(x: c.x + w / 2, y: c.y + h * 0.60))
        path.stroke()

    case .ringCheck:
        // 白色圆环 + 环内对勾
        let ringR = rect.width * 0.295
        let ring = NSBezierPath(ovalIn: CGRect(x: c.x - ringR, y: c.y - ringR,
                                              width: ringR * 2, height: ringR * 2))
        ring.lineWidth = strokeWidth(base: rect.width * 0.072, px: px, boost: 0.12)
        ring.stroke()

        let cw = ringR * 0.92
        let ch = ringR * 0.62
        let mark = NSBezierPath()
        mark.lineWidth = ring.lineWidth
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        mark.move(to: CGPoint(x: c.x - cw / 2, y: c.y + ch * 0.04))
        mark.line(to: CGPoint(x: c.x - cw * 0.10, y: c.y - ch * 0.52))
        mark.line(to: CGPoint(x: c.x + cw / 2, y: c.y + ch * 0.58))
        mark.stroke()
    }
}

/// 在指定上下文尺寸下渲一个像素级精确的 PNG。
func pngData(px: Int, variant: Variant) -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.shouldAntialias = true
    drawIcon(px: px, variant: variant)
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:]) ?? Data()
}

// MARK: - 变体对比预览图

func writeSheet(to path: String) {
    let cols: [(label: String, px: Int, scale: CGFloat)] = [
        ("176px", 176, 1), ("64px", 64, 1),
        ("32px", 32, 1), ("16px", 16, 1), ("16px ×10", 16, 10)
    ]
    let labelW: CGFloat = 200
    let gap: CGFloat = 26
    let pad: CGFloat = 32
    let headerH: CGFloat = 64
    let rowH = 176 + gap

    let colWidths = cols.map { CGFloat($0.px) * $0.scale }
    let width = Int(pad * 2 + labelW + colWidths.reduce(0, +) + gap * CGFloat(cols.count))
    let height = Int(pad * 2 + headerH + rowH * CGFloat(Variant.allCases.count))

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor(white: bold ? 0.12 : 0.45, alpha: 1)
        ]
        NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: x, y: y))
    }

    // 表头
    var x = pad + labelW
    let headerY = CGFloat(height) - pad - 28
    for col in cols {
        label(col.label, x: x, y: headerY, size: 20, bold: true)
        x += colWidths[cols.firstIndex { $0.label == col.label }!] + gap
    }

    // 每行一个变体：同时画出原尺寸与小尺寸放大图
    for (row, variant) in Variant.allCases.enumerated() {
        let rowTop = CGFloat(height) - pad - headerH - rowH * CGFloat(row)
        let rowBottom = rowTop - rowH
        let rowCenterY = rowBottom + rowH / 2

        if row > 0 {
            NSColor(white: 0.9, alpha: 1).setFill()
            NSRect(x: pad, y: rowTop + gap / 2, width: CGFloat(width) - pad * 2, height: 1).fill()
        }

        label(variant.title, x: pad, y: rowCenterY - 14, size: 26, bold: true)

        var cx = pad + labelW
        for col in cols {
            let side = CGFloat(col.px) * col.scale
            let png = pngData(px: col.px, variant: variant)
            if let img = NSImage(data: png) {
                img.draw(in: NSRect(x: cx, y: rowCenterY - side / 2, width: side, height: side),
                         from: .zero, operation: .sourceOver, fraction: 1)
            }
            cx += side + gap
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote sheet to \(path) (\(width)×\(height))")
    }
}

// MARK: - 入口

var outDir = "Resources/AppIcon.iconset"
var variant: Variant = .spark
var sheetPath: String?

var argv = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < argv.count {
    if argv[i] == "--sheet" {
        i += 1
        sheetPath = i < argv.count ? argv[i] : "appicon-variants.png"
    } else if let parsed = Variant(rawValue: argv[i]) {
        variant = parsed
    } else {
        outDir = argv[i]
    }
    i += 1
}

if let sheetPath {
    writeSheet(to: sheetPath)
    exit(0)
}

let dir = URL(fileURLWithPath: outDir)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

for spec in sizes {
    do {
        try pngData(px: spec.px, variant: variant).write(to: dir.appendingPathComponent(spec.name))
    } catch {
        FileHandle.standardError.write(Data("failed to write \(spec.name): \(error)\n".utf8))
        exit(1)
    }
}
print("wrote \(sizes.count) images to \(dir.path) (variant: \(variant.rawValue))")
