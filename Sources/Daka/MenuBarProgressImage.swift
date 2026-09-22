import AppKit

/// 顶部菜单栏图标：以 Core Graphics 绘制为 template NSImage。
/// MenuBarExtra 的 SwiftUI label 不可靠渲染自定义 Shape，故改为图片；
/// template 图片只取 alpha 通道，由系统按菜单栏前景着色，天然适配深浅色。
enum MenuBarProgressImage {
    /// - Parameters:
    ///   - fraction: 外环进度 0...1（未打上班卡为 0，即只显示淡环）。
    ///   - badge: 是否叠加右上角待办实心点。
    static func make(fraction: CGFloat, badge: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let lineWidth: CGFloat = 2
            let radius = (rect.width - lineWidth) / 2 - 0.5
            let ringRect = NSRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)

            // 淡底环：状态轨道，恒在。
            NSColor.black.withAlphaComponent(0.28).setStroke()
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = lineWidth
            track.stroke()

            // 进度弧：随工作进度填充。
            let sweep = 360 * min(1, max(0, fraction))
            if sweep > 0.5 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius,
                              startAngle: 90 - sweep, endAngle: 90)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            // 中心芒星：logo 身份，所有状态恒在（缩小以让外环套住它）。
            NSColor.black.setFill()
            sparkPath(center: center, size: 8.5).fill()

            if badge {
                let r: CGFloat = 3
                let dot = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 2 * r,
                                                      y: rect.maxY - 2 * r,
                                                      width: 2 * r, height: 2 * r))
                NSColor.black.setFill()
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 复刻 App logo 中心的扁平四角星芒（竖向略长于横向，四边内凹）。
    private static func sparkPath(center c: CGPoint, size s: CGFloat) -> NSBezierPath {
        let rv = s * 0.50
        let rh = s * 0.46
        let k: CGFloat = 0.20
        let points = [CGPoint(x: c.x, y: c.y + rv), CGPoint(x: c.x + rh, y: c.y),
                      CGPoint(x: c.x, y: c.y - rv), CGPoint(x: c.x - rh, y: c.y)]
        let path = NSBezierPath()
        path.move(to: points[0])
        for i in 0..<4 {
            let from = points[i]
            let to = points[(i + 1) % 4]
            let control = CGPoint(x: c.x + (from.x - c.x) * k + (to.x - c.x) * k,
                                  y: c.y + (from.y - c.y) * k + (to.y - c.y) * k)
            path.curve(to: to, controlPoint: control)
        }
        path.close()
        return path
    }
}
