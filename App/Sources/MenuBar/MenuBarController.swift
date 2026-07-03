import AppKit

/// 菜单栏图标控制器：左键弹出菜单（显示面板 / 退出）。
/// 不设置 statusItem.menu（否则 Cmd+拖动会把图标从菜单栏移除）。
@MainActor
public final class MenuBarController {

    private nonisolated(unsafe) var statusItem: NSStatusItem?
    private let onShowPanel: () -> Void

    public init(onShowPanel: @escaping () -> Void) {
        self.onShowPanel = onShowPanel
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

        // 左键弹出菜单（手动 popUp，避免 Cmd+拖动移除）
        button.target = self
        button.action = #selector(iconClicked)
        button.sendAction(on: [.leftMouseUp])
    }

    @objc private func iconClicked() {
        guard let button = statusItem?.button else { return }
        let menu = buildMenu()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: "显示面板",
            action: #selector(showPanel),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
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
