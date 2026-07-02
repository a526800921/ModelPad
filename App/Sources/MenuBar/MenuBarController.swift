import AppKit

/// 菜单栏图标控制器：左键显示面板，右键弹出菜单（显示面板 / 退出）。
public final class MenuBarController {

    private var statusItem: NSStatusItem?
    private let onShowPanel: () -> Void

    public init(onShowPanel: @escaping () -> Void) {
        self.onShowPanel = onShowPanel
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        button.image = NSImage(
            systemSymbolName: "cpu",
            accessibilityDescription: "ModelPad"
        )

        // 左键点击 → 显示面板
        button.target = self
        button.action = #selector(iconClicked)
        button.sendAction(on: [.leftMouseUp, .leftMouseDown])

        // 右键点击 → 弹出菜单（系统自动处理右键弹出 menu）
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "显示面板",
            action: #selector(showPanel),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "退出",
            action: #selector(quitApp),
            keyEquivalent: ""
        ))
        statusItem?.menu = menu
    }

    @objc private func iconClicked() {
        onShowPanel()
    }

    @objc private func showPanel() {
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
}
