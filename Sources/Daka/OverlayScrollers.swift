import AppKit
import SwiftUI

/// 把 SwiftUI 的 ScrollView 切换成 macOS 悬浮式（overlay）滚动条。
///
/// 背景：SwiftUI 没有暴露滚动条样式的切换接口，`NSScroller.preferredScrollerStyle` 又是只读的，
/// 只能逐个改 `NSScrollView.scrollerStyle`。而接了鼠标之后 macOS 会把滚动条偏好切到
/// 「始终显示」，此时用的是 legacy 样式 —— 一条带底槽的宽滚动条，还会占掉内容宽度，
/// 这正是滚动条显得笨重的原因。改成 overlay 后：细窄半透明、浮在内容之上、
/// 滚动时淡入、停止后自动淡出。
///
/// 实现要点：SwiftUI 会把 `background` 里的 representable 提升成 NSHostingView 的直接子视图，
/// 也就是 NSScrollView 的**兄弟节点**，所以 `enclosingScrollView` 拿不到东西，
/// 必须从窗口根部向下查找。
struct OverlayScrollersConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Probe)?.applyStyle()
    }

    final class Probe: NSView {
        private var styleObserver: NSObjectProtocol?

        /// 探针只用来定位 NSScrollView，不参与鼠标命中，避免挡住内容上的按钮。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard window != nil else {
                // 离开窗口时摘掉通知，避免观察者长期驻留。
                if let styleObserver {
                    NotificationCenter.default.removeObserver(styleObserver)
                    self.styleObserver = nil
                }
                return
            }

            observePreferredStyle()
            applyStyle()
            // 同一轮布局里 NSScrollView 可能还没建好（例如刚切换页面），补一次。
            DispatchQueue.main.async { [weak self] in self?.applyStyle() }
        }

        /// 插拔鼠标会让系统把样式改回 legacy，收到变更通知后再压回 overlay。
        private func observePreferredStyle() {
            guard styleObserver == nil else { return }
            styleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.applyStyle() }
            }
        }

        func applyStyle() {
            guard let contentView = window?.contentView else { return }
            for scrollView in Self.scrollViews(in: contentView) {
                if scrollView.scrollerStyle != .overlay {
                    scrollView.scrollerStyle = .overlay
                }
                if !scrollView.autohidesScrollers {
                    scrollView.autohidesScrollers = true
                }
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            func walk(_ current: NSView) {
                if let scrollView = current as? NSScrollView { result.append(scrollView) }
                for sub in current.subviews { walk(sub) }
            }
            walk(view)
            return result
        }
    }
}

extension View {
    /// 让界面上的滚动视图使用悬浮滚动条：浮在内容之上，滚动时出现，停止后淡出。
    ///
    /// 注意不能给探针加 `.frame(width: 0, height: 0)` —— 零尺寸视图会被 SwiftUI 直接跳过、
    /// 根本不挂载到视图树上。让它随内容尺寸挂载即可（它不绘制、不参与命中测试）。
    func overlayScrollers() -> some View {
        background(OverlayScrollersConfigurator())
    }
}
