# 阶段 5 缺陷诊断报告（2026-07-02）

## 背景

用户反馈以下问题，本次只做文档诊断，不修改代码：

1. `Cmd+Q` 仍然无法退出程序。
2. 已增加 2 个模型配置，启动一个模型后切换到另一个模型，日志列表没有随之切换，仍保留旧内容。
3. 点击“启动”按钮时，界面会无响应几秒钟。

## 诊断方式

- 代码级审查：`App/Sources/ModelPadApp.swift`、`App/Sources/AppDelegate.swift`、`App/Sources/AppViewModel.swift`、`App/Sources/Views/LogView.swift`、`App/Sources/Views/ModelDetailView.swift`、`Sources/ModelPadCore/Process/ModelProcessManager.swift`、`Sources/ModelPadCore/API/APIServer.swift`。
- 未做代码修改。
- 未做 GUI 自动化复现。当前问题依赖真实 macOS 窗口、菜单和用户交互，建议后续实现修复时补充最小手动验收脚本或 UI 测试说明。

## 问题 1：`Cmd+Q` 仍然无法退出

### 相关代码

- `App/Sources/ModelPadApp.swift`
  - `CommandGroup(replacing: .appTermination)` 注册“退出 ModelPad”命令。
  - 命令执行 `NSApp.terminate(nil)`。
- `App/Sources/AppDelegate.swift`
  - `applicationShouldTerminate(_:)` 返回 `.terminateLater`。
  - 设置 `isTerminating = true`。
  - 主线程同步调用 `viewModel.stopAllRunningProcesses()`。
  - 后台线程调用 `viewModel.apiServer.stop()`，然后回到主线程调用 `sender.reply(toApplicationShouldTerminate: true)`。
- `Sources/ModelPadCore/API/APIServer.swift`
  - `stop()` 内部同步执行 `channel?.close().wait()` 和 `group?.syncShutdownGracefully()`。
- `Sources/ModelPadCore/Process/ModelProcessManager.swift`
  - `stop(modelId:)` 会同步等待进程退出，最多先等待 5 秒，必要时 `SIGKILL` 后 `waitUntilExit()`。

### 可能原因排序

1. **退出路径过度依赖 `.terminateLater`，且没有超时兜底。**
   - 如果 `apiServer.stop()` 或某个托管进程停止卡住，`reply(toApplicationShouldTerminate: true)` 就不会执行，App 会一直处于“等待退出确认”的状态。
   - 当前代码没有记录失败原因，也没有超时后强制确认退出的策略。

2. **`stopAllRunningProcesses()` 在主线程同步执行，可能先阻塞 UI 和退出流程。**
   - 如果有多个模型在运行，或者某个模型停止慢，主线程会逐个等待。
   - 用户体感会是 `Cmd+Q` 后没有反应，甚至误判为完全无法退出。

3. **重复触发退出时，`isTerminating == true` 分支返回 `.terminateLater`，但不再安排新的 reply。**
   - 如果第一次退出请求已经丢失、卡住或未完成，第二次 `Cmd+Q` 只会继续返回 `.terminateLater`。
   - 这会放大“退不了”的现象。

### 建议修复方向

- 将退出流程设计为单一异步任务：
  - 第一次退出请求返回 `.terminateLater`。
  - 所有清理放入后台任务。
  - 清理完成或超时后，主线程只调用一次 `reply(toApplicationShouldTerminate: true)`。
- 给 API Server 停止和进程停止增加总超时兜底。
- `isTerminating == true` 时不要再次返回一个没有 reply 的 `.terminateLater`。可选择：
  - 直接返回 `.terminateNow`，或
  - 保持等待但确保已有退出任务一定会 reply，且有超时。
- 避免在主线程同步等待进程停止。

### 验收标准

- 不启动任何模型时，`Cmd+Q` 能在 1 秒内退出。
- 启动 1 个普通模型后，`Cmd+Q` 能退出，并停止托管进程。
- 启动一个忽略 `SIGTERM` 的模型后，`Cmd+Q` 最终仍能退出，不无限等待。
- `Cmd+Q` 连续按多次，不会进入无法回复的退出等待状态。
- 退出后 `127.0.0.1:9999` 不再响应，托管模型进程无残留。

## 问题 2：切换模型后日志列表仍显示旧内容

### 相关代码

- `App/Sources/Views/ModelDetailView.swift`
  - 通过 `if let model = viewModel.editingModel` 渲染当前模型详情。
  - 日志区创建为 `LogView(modelId: model.id)`。
- `App/Sources/Views/LogView.swift`
  - `logs` 是 `@State private var logs: [ModelLogEntry] = []`。
  - 日志内容只在 `timer` 每秒触发时执行 `logs = viewModel.logs(for: modelId)`。
  - 没有 `onAppear` 初始化日志。
  - 没有 `onChange(of: modelId)` 清空或立即刷新日志。
  - `ForEach` 使用 `Array(logs.enumerated())` 的 offset 作为身份。

### 直接原因

`LogView` 把日志快照保存在本地 `@State logs`，而这个状态不会因为 `modelId` 改变而自动清空。SwiftUI 可能复用同一个 `LogView` 视图身份，因此切换模型时旧模型日志会继续留在 `logs` 中，直到下一次定时刷新；如果订阅或视图身份没有按模型重新建立，用户会持续看到旧日志。

### 建议修复方向

- 让日志视图跟模型 ID 建立明确身份：
  - 在 `ModelDetailView` 中对 `LogView(modelId: model.id)` 增加 `.id(model.id)`，强制模型切换时重建日志视图。
- 或者让 `LogView` 在 `modelId` 变化时立即刷新：
  - `onAppear` 时加载 `viewModel.logs(for: modelId)`。
  - `onChange(of: modelId)` 时先清空 `logs`，再加载新模型日志。
- 更稳妥的长期方案：
  - 不在 `LogView` 内持久保存跨模型的 `@State logs`，而由 ViewModel 暴露“当前选中模型日志”或按 `selectedModelId` 派生日志。

### 验收标准

- 创建两个模型 A/B。
- 启动 A，使 A 产生日志。
- 切换到 B 后，日志区应立即显示 B 的日志；如果 B 没日志，应立即为空。
- 再切回 A，应显示 A 的日志。
- 清空 B 日志不影响 A 日志。

## 问题 3：点击“启动”按钮后 UI 无响应几秒

### 相关代码

- `App/Sources/Views/ModelDetailView.swift`
  - “启动”按钮直接调用 `viewModel.startModel(model.id)`。
- `App/Sources/AppViewModel.swift`
  - `AppViewModel` 标注 `@MainActor`。
  - `startModel(_:)` 在主线程执行：
    - `autoSaveBeforeStart(for:)`
    - 查找模型配置
    - `processManager.start(config:)`
    - `refreshStatus()`
- `Sources/ModelPadCore/Process/ModelProcessManager.swift`
  - `start(config:)` 是同步函数。
  - 启动后如果配置了端口，会同步调用 `TCPHealthChecker.check(... timeout: healthCheckTimeout)`。
  - 默认健康检查超时是 30 秒。
  - 健康检查失败路径还会同步终止进程并等待退出。

### 直接原因

启动按钮在主线程调用同步启动流程。只要 `processManager.start(config:)` 内部做了耗时操作，SwiftUI 主线程就会被阻塞，表现为界面无响应。

最明显的阻塞点是端口健康检查：

- 有端口配置时，`TCPHealthChecker.check` 会同步等待端口可连接。
- 模型启动需要几秒时，按钮点击后的几秒都发生在主线程。
- 如果端口一直不可用，理论上最多可能阻塞到健康检查超时。

### 次要原因

- `autoSaveBeforeStart` 和 `ConfigStore.save` 也在主线程执行磁盘 IO。
- `startAllModels()` 逐个同步启动模型，如果后续阶段使用全部启动，会放大阻塞。

### 建议修复方向

- 将启动、停止、重启、全部启动、全部停止改为异步任务，不在主线程执行阻塞逻辑。
- UI 点击后立即把状态切到 `starting`，按钮进入禁用或 loading 状态。
- 健康检查完成后再回主线程刷新状态。
- 为启动操作提供可见反馈：
  - 按钮显示“启动中”。
  - 状态徽标立即变为“启动中”。
  - 失败时展示错误原因。
- 配置保存可以保留在主线程触发，但实际磁盘写入建议放后台，或确保文件写入足够快并有错误反馈。

### 验收标准

- 点击“启动”后 UI 不冻结，窗口可移动、模型列表可选中。
- 点击后 100ms 内状态显示为“启动中”。
- 有端口模型启动期间，日志和状态仍能刷新。
- 健康检查失败不会导致 UI 卡死。
- 全部启动多个模型时，界面仍可响应。

## 建议的后续处理顺序

1. 先修 `Cmd+Q` 退出，因为它影响 App 生命周期和用户兜底操作。
2. 再修启动按钮阻塞，因为它影响所有进程控制交互。
3. 最后修日志切换，因为修复范围局限在日志视图身份和刷新逻辑。

## 建议补充测试或验收

- `Cmd+Q` 退出需要手动验收或 UI 自动化验收，单元测试覆盖有限。
- 日志切换可以补 ViewModel 或 View 层测试；如果当前测试框架不适合 SwiftUI View，可先用手动验收清单记录。
- 启动按钮无响应建议增加一个“慢健康检查”替身或测试 seam，用于证明启动动作不会阻塞 MainActor。

## 结论

三个问题都不是配置或数据契约问题，主要集中在阶段 4 App/UI 集成层：

- 退出问题：生命周期清理流程缺少超时和可靠 reply，且主线程参与同步停止进程。
- 日志问题：日志视图本地 `@State` 没有随 `modelId` 切换重置。
- 卡顿问题：按钮直接在 MainActor 上执行同步进程启动和 TCP 健康检查。

后续如果用户明确同意修改代码，建议按本文档的处理顺序进入实现。
