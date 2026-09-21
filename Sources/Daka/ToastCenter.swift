import AppKit
import SwiftUI

/// 通用 toast 弱提示：模仿微信消息提示的深色圆角卡片，浮在所在屏右上角，停留数秒后自动淡出。
/// 不抢焦点、不打断输入；多条提示会像微信一样层叠（新的从右侧滑入插到最上，旧的被顶下去）。
///
/// 动画分工（关键：窗口不动，卡片自己动）：
/// - 窗口只负责「按卡片数量撑到对应高度 + 上屏 / 下屏」，动画期间窗口尺寸不变；
/// - 卡片入场从窗口右边界外滑入，出场右移淡出，被顶下去的位移同样是 spring 插值，
///   全部在窗口内由 Core Animation 完成。相比直接动画窗口 frame（走窗口服务器、容易抖动掉帧），
///   这种方式更跟手；
/// - 卡片高度统一，所以卡片数量一确定窗口高度就是已知值，可以先撑开窗口再播动画，
///   避免滑入 / 下移过程中被窗口边界裁掉。
@MainActor
final class ToastCenter {
    struct Toast: Equatable, Identifiable {
        /// 每次展示的唯一标识：文案相同也会重新播放入场动画。
        let uid = UUID()
        var title: String
        var body: String
        var icon: String
        var tint: Color = ToastPalette.brand

        var id: UUID { uid }

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.title == rhs.title && lhs.body == rhs.body
                && lhs.icon == rhs.icon && lhs.tint == rhs.tint
        }
    }

    /// 卡片与窗口尺寸。卡片是不透明的纯色块，没有投影，所以窗口只在右侧留出滑入距离
    /// （卡片起点落在窗口外），四周留白很小——留白在屏幕上是完全透明的，不会出现灰色底衬。
    enum Metrics {
        static let cardWidth: CGFloat = 340
        /// 统一卡片高度：正文 1 行时内容居中留白，比高度忽高忽低更整齐，也让窗口高度可精确预判。
        static let cardHeight: CGFloat = 76
        static let cardSpacing: CGFloat = 8
        static let sideInset: CGFloat = 12
        static let topInset: CGFloat = 8
        static let bottomInset: CGFloat = 8

        static func panelSize(cards: Int) -> CGSize {
            let count = max(1, cards)
            let height = topInset
                + CGFloat(count) * cardHeight
                + CGFloat(count - 1) * cardSpacing
                + bottomInset
            return CGSize(width: cardWidth + sideInset * 2, height: height)
        }

        /// 入场位移：起点完全落在窗口右边界外，视觉上就是「从屏幕右缘滑进来」。
        static var enterOffset: CGFloat { cardWidth + sideInset }
        /// 出场位移：只向右挪一点并淡出。
        static let exitOffset: CGFloat = 24
    }

    static let shared = ToastCenter()

    /// 常规停留时长：喝水/走动等弱提示默认 4 秒。
    private let displayDuration: TimeInterval = 4
    /// 同时最多展示几张卡，超出时挤掉最早的一条。
    private static let maxVisible = 3
    /// 层叠动画：新卡滑入、旧卡被顶下去。
    private static let stackSpring = Animation.spring(response: 0.40, dampingFraction: 0.84)
    /// 收尾动画：最后一张淡出。
    private static let closeEase = Animation.easeIn(duration: 0.24)
    /// 收尾动画时长 + 余量，用于决定何时下屏。
    private static let closeSettle: TimeInterval = 0.28
    /// 层叠位移动画的收敛时间，用于决定何时收缩窗口。
    private static let stackSettle: TimeInterval = 0.5

    private let model = ToastModel()
    private var panel: NSPanel?
    /// 每张卡各自的自动收起定时器与截止时间（按 uid 索引）。
    private var timers: [UUID: Timer] = [:]
    private var deadlines: [UUID: Date] = [:]
    /// 悬停期间暂存的剩余时长：悬停暂停倒计时，移开后接着走完。
    private var paused: [UUID: TimeInterval] = [:]
    private var isHovering = false

    // MARK: - 对外接口

    func show(_ toast: Toast, duration: TimeInterval? = nil) {
        let panel = ensurePanel()
        let seconds = duration ?? displayDuration
        let isFirst = model.toasts.isEmpty

        var stack = model.toasts
        stack.insert(toast, at: 0)
        if stack.count > Self.maxVisible {
            // 超出容量：最早的一条直接让位。
            for dropped in stack[Self.maxVisible...] {
                cancelTimer(dropped.uid)
            }
            stack = Array(stack.prefix(Self.maxVisible))
        }

        // 先把窗口撑到新高度（右上角锚定、尺寸瞬变不可见），卡片才开始滑动。
        applyFrame(cards: stack.count)
        if isFirst {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        withAnimation(Self.stackSpring) { model.toasts = stack }
        scheduleTimer(for: toast.uid, seconds: seconds)
    }

    /// 收起指定卡片（点击卡片本身）。
    func dismiss(_ uid: UUID) {
        removeToast(uid)
    }

    /// 收起全部卡片（测试面板的「立即收起」）。
    func dismiss() {
        guard !model.toasts.isEmpty else { return }
        for toast in model.toasts { cancelTimer(toast.uid) }
        withAnimation(Self.closeEase) { model.toasts = [] }
        hidePanelWhenEmpty()
    }

    /// 悬停时暂停倒计时，移开后接着走完——给用户留出看完长文案的时间。
    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        if hovering {
            paused = deadlines.mapValues { max(0.6, $0.timeIntervalSinceNow) }
            timers.values.forEach { $0.invalidate() }
            timers.removeAll()
            deadlines.removeAll()
        } else if !paused.isEmpty {
            let resume = paused
            paused.removeAll()
            for (uid, seconds) in resume where model.toasts.contains(where: { $0.uid == uid }) {
                scheduleTimer(for: uid, seconds: seconds)
            }
        }
    }

    /// 屏幕布局变化（热插拔/分辨率调整）时重定位。
    func repositionIfNeeded() {
        guard let panel, panel.isVisible else { return }
        applyFrame(cards: model.toasts.count)
    }

    // MARK: - 面板管理

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = Metrics.panelSize(cards: 1)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let hosting = NSHostingView(rootView: ToastView(
            model: model,
            onHover: { [weak self] hovering in self?.setHovering(hovering) },
            onTap: { [weak self] uid in self?.dismiss(uid) }))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        // 关掉 NSHostingView 的自适应尺寸：内容用 maxWidth/maxHeight 撑满，若不关它可能
        // 反过来把 contentView 收缩到内容固有尺寸，导致窗口在屏但什么都看不见。
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(targetFrame(cards: 1), display: false)
        self.panel = panel
        return panel
    }

    /// 按卡片数量调整窗口尺寸，右上角锚定不动（只向下生长 / 收缩）。
    private func applyFrame(cards: Int) {
        guard let panel else { return }
        let size = Metrics.panelSize(cards: cards)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(targetFrame(cards: cards), display: true)
    }

    /// toast 落在哪块屏：优先鼠标所在屏（用户注意力所在），回退 NSScreen.main、再回退首屏。
    ///
    /// 多屏环境下 `NSScreen.main` 指的是「含当前 key window 的屏」，应用没窗口或焦点在副屏时
    /// 会指向副屏，导致右上角提示跑到另一块屏上（外接屏场景实测过）。
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return hit
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// 贴近所在屏右上角（类系统通知位置）：上边缘与右边缘固定，高度随卡片数量变化。
    private func targetFrame(cards: Int) -> NSRect {
        let size = Metrics.panelSize(cards: cards)
        guard let screen = activeScreen() else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        return NSRect(x: visible.maxX - size.width - 8,
                      y: visible.maxY - size.height - 6,
                      width: size.width,
                      height: size.height)
    }

    // MARK: - 倒计时与收起

    private func scheduleTimer(for uid: UUID, seconds: TimeInterval) {
        cancelTimer(uid)
        deadlines[uid] = Date().addingTimeInterval(seconds)
        guard !isHovering else { return }
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.removeToast(uid) }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[uid] = timer
    }

    private func cancelTimer(_ uid: UUID) {
        timers[uid]?.invalidate()
        timers[uid] = nil
        deadlines[uid] = nil
        paused[uid] = nil
    }

    private func removeToast(_ uid: UUID) {
        guard model.toasts.contains(where: { $0.uid == uid }) else { return }
        cancelTimer(uid)
        var stack = model.toasts
        stack.removeAll { $0.uid == uid }

        if stack.isEmpty {
            // 最后一张：短促淡出后下屏。
            withAnimation(Self.closeEase) { model.toasts = [] }
            hidePanelWhenEmpty()
        } else {
            // 其余卡片上移要靠当前窗口高度兜住，动画结束再缩窗口（缩掉的是底部空白，看不见）。
            withAnimation(Self.stackSpring) { model.toasts = stack }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stackSettle) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.model.toasts.count == stack.count else { return }
                    self.applyFrame(cards: stack.count)
                }
            }
        }
    }

    /// 等淡出动画走完再下屏；期间若有新 toast 进来则放弃下屏。
    private func hidePanelWhenEmpty() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeSettle) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.toasts.isEmpty, let panel = self.panel else { return }
                panel.orderOut(nil)
            }
        }
    }
}

@MainActor
final class ToastModel: ObservableObject {
    /// 当前展示的卡片，索引 0 在最上面（最新的一条）。
    @Published var toasts: [ToastCenter.Toast] = []
}

/// 窗口内容：自上而下的一叠卡片。窗口本身不动，位置动画全由卡片自己完成。
struct ToastView: View {
    @ObservedObject var model: ToastModel
    var onHover: (Bool) -> Void
    var onTap: (UUID) -> Void

    var body: some View {
        VStack(spacing: ToastCenter.Metrics.cardSpacing) {
            ForEach(model.toasts) { toast in
                ToastCard(toast: toast, onTap: { onTap(toast.uid) })
                    .transition(.asymmetric(
                        insertion: .offset(x: ToastCenter.Metrics.enterOffset).combined(with: .opacity),
                        removal: .offset(x: ToastCenter.Metrics.exitOffset).combined(with: .opacity)))
            }
        }
        .padding(.top, ToastCenter.Metrics.topInset)
        .onHover(perform: onHover)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 单张 toast 卡片：微信提示样式——深色圆角底 + 方形头像 + 加粗标题 + 次级正文。
private struct ToastCard: View {
    let toast: ToastCenter.Toast
    var onTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.97))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(toast.body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: ToastCenter.Metrics.cardWidth,
               height: ToastCenter.Metrics.cardHeight,
               alignment: .leading)
        // 纯色不透明底：不用材质（会在透明窗口里铺一层灰色半透明背衬），也不加投影。
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    /// 卡片底色：不透明深色，不跟随系统亮/暗外观（微信提示固定是深色卡片）。
    private var surface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.173, green: 0.173, blue: 0.180))
    }

    /// 方形头像：微信头像是圆角方块，这里用提醒类型色 + 白色符号，一眼能区分哪类提示。
    private var avatar: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(toast.tint)
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: toast.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}
