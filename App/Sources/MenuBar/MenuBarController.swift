import AppKit

/// 菜单栏图标控制器：左键打开面板，右键弹出菜单（显示面板 / 退出）。
/// 实现方式：
/// - 不设置 NSStatusItem.menu（设置后 AppKit 会接管全部点击，左右键都弹菜单）。
/// - 左键通过 button.action → iconClicked 打开面板。
/// - 右键通过 NSEvent.addLocalMonitorForEvents 捕获并弹出自定义 NSMenu。
@MainActor
public final class MenuBarController {

    private nonisolated(unsafe) var statusItem: NSStatusItem?
    private nonisolated(unsafe) var rightClickMonitor: Any?
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

        // 左键 → 打开主面板
        button.target = self
        button.action = #selector(iconClicked)
        button.sendAction(on: [.leftMouseUp])

        // 右键 → 弹出菜单（通过事件监听器独立处理，不走 statusItem.menu）
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp]) { [weak self] event in
            guard let self = self,
                  let button = self.statusItem?.button else {
                return event
            }

            // 仅当右键点击位于状态栏按钮区域内时弹出菜单
            let locationInButton = button.convert(event.locationInWindow, from: nil)
            if button.bounds.contains(locationInButton) {
                let menu = self.buildMenu()
                menu.popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: button.bounds.height),
                    in: button
                )
                return nil  // 消费事件，防止继续传递
            }
            return event
        }
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
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }
}
