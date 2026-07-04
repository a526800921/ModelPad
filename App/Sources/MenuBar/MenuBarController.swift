import AppKit
import ModelPadCore

/// 菜单栏图标控制器：左键弹出菜单，展示全部已配置服务及运行状态点
///（运行中绿点、停止灰点）。通过注入 `AppViewModel` 读取服务列表和状态，
/// 不直接创建业务对象。
@MainActor
public final class MenuBarController: NSObject {

    private nonisolated(unsafe) var statusItem: NSStatusItem?
    private let onShowPanel: () -> Void
    private let appViewModel: AppViewModel

    /// 状态点尺寸。
    private static let dotSize: CGFloat = 8

    /// 预生成的圆形状态图，按颜色缓存避免每次重建。
    private static let greenDot: NSImage = MenuBarController.makeDot(color: .systemGreen, size: dotSize)
    private static let yellowDot: NSImage = MenuBarController.makeDot(color: .systemYellow, size: dotSize)
    private static let redDot: NSImage = MenuBarController.makeDot(color: .systemRed, size: dotSize)
    private static let grayDot: NSImage = MenuBarController.makeDot(color: .systemGray, size: dotSize)

    public init(
        onShowPanel: @escaping () -> Void,
        appViewModel: AppViewModel
    ) {
        self.onShowPanel = onShowPanel
        self.appViewModel = appViewModel
        super.init()
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        let image = NSImage(
            systemSymbolName: "cpu",
            accessibilityDescription: "ModelPad"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        // 固定 frame 防止被邻近长状态栏 app 挤掉
        button.frame = NSRect(x: 0, y: 0, width: NSStatusItem.squareLength, height: NSStatusItem.squareLength)

        // 左键弹出下拉菜单
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    /// 为菜单项构造状态点图（不显示状态文字，仅用圆点表示）。
    private func dotImage(for status: ModelStatus) -> NSImage? {
        switch status {
        case .running:  return Self.greenDot
        case .starting: return Self.yellowDot
        case .error:    return Self.redDot
        case .stopped:  return Self.grayDot
        }
    }

    /// 重绘全部菜单项：服务列表 → 分隔线 → 显示面板 / 退出。
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 菜单打开前触发一次轻量刷新，不新增独立轮询
        appViewModel.refreshStatus()

        // ---- 服务列表 ----
        let models = appViewModel.models
        let statuses = appViewModel.statusMessages
        for model in models {
            let status = statuses[model.id] ?? .stopped
            let item = NSMenuItem(
                title: model.name,
                action: nil,
                keyEquivalent: ""
            )
            item.image = dotImage(for: status)
            menu.addItem(item)
        }

        // ---- 分隔 + 固定操作（有服务时才加分隔线） ----
        if !models.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        let showItem = NSMenuItem(
            title: "显示面板",
            action: #selector(showPanel),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc func showPanel() {
        onShowPanel()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    deinit {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - 状态点绘制

    /// 创建实心圆 `NSImage`，对齐主面板的 ModelRow 颜色。
    private static func makeDot(color: NSColor, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.setFill()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSBezierPath(ovalIn: rect).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

// MARK: - NSMenuDelegate

extension MenuBarController: NSMenuDelegate {
    /// 菜单打开前刷新全部菜单项，确保状态为最新。
    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
