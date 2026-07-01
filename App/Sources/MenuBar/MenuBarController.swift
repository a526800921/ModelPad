import AppKit

/// 菜单栏图标控制器：左键点击打开面板，不弹出菜单。
public final class MenuBarController {

    private var statusItem: NSStatusItem?
    private let onLeftClick: () -> Void

    public init(onLeftClick: @escaping () -> Void) {
        self.onLeftClick = onLeftClick
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "cpu",
                accessibilityDescription: "ModelPad"
            )
            button.target = self
            button.action = #selector(iconClicked)
        }

        // 不设置 menu，左键点击走 action
    }

    @objc private func iconClicked() {
        onLeftClick()
    }

    deinit {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }
}
