# 计划：ModelPad 菜单栏服务列表

## 目标

点击菜单栏 icon 打开下拉菜单时，菜单内直接展示全部已配置服务，并用“状态点 + 名称”的简洁样式表示服务是否正在运行：运行中显示绿点，停止或未运行显示灰点。

本计划是对已完成的 [ModelPad 菜单栏常驻和启动配置增强](modelpad-menu-bar-agent.md) 的后续体验增强。此前菜单栏计划明确不做菜单栏模型列表；2026-07-04 的新需求改变了这个范围判断，因此用独立候选计划承载，避免改写已完成阶段的历史范围。

## 范围

- 菜单栏 icon 点击后仍打开下拉菜单。
- 下拉菜单展示全部已配置服务。
- 每个服务菜单项至少包含：
  - 状态点：服务运行中时显示绿色状态点，停止或未运行时显示灰色状态点。
  - 服务名称：使用配置中的服务名称。
- 服务菜单项在阶段 1 保持只读，不触发启停、重启或打开详情。
- 服务列表位于菜单顶部，随后使用分隔线区分 `显示面板` 和 `退出`。
- 现有 `显示面板` 和 `退出` 入口继续保留。
- 服务列表状态应与主面板 / API 启停后的当前状态一致。
- 菜单栏下拉菜单打开前触发一次轻量状态刷新，平时不新增独立轮询。

## 非范围

- 不在本计划内做菜单栏服务启停、重启、全部启动或全部停止。
- 不新增资源监控、端口、PID、日志预览等复杂信息。
- 不改变本地 HTTP API 契约。
- 不改变现有模型配置 Schema。

## 当前阶段

当前阶段：阶段 1 已完成。

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | 菜单栏下拉菜单展示服务列表和状态点 | `modelpad-menu-bar-agent` 已完成；服务列表只读；运行中绿点、停止灰点；菜单打开前轻量刷新状态；`MenuBarController` 通过注入读取现有状态数据源 | 手动点击菜单栏 icon，确认全部服务展示、运行中服务有绿点、停止服务有灰点；API / 主面板启停后菜单状态同步 | 已完成 |

## Step 0 证据

- 当前已完成的菜单栏下拉菜单只包含 `显示面板` 和 `退出`。
- `modelpad-menu-bar-agent` 历史范围曾明确“不新增菜单栏模型列表、启停模型、全部启动或全部停止功能”。
- 用户于 2026-07-04 新增需求：点击菜单栏 icon 时，下拉菜单里面展示全部服务，样式只需要表示启动状态的绿点加名称。
- 代码基线：
  - `App/Sources/MenuBar/MenuBarController.swift` 当前在 `setup()` 中设置 `statusItem?.menu = buildMenu()`，`buildMenu()` 只生成 `显示面板`、分隔线和 `退出`。
  - `App/Sources/AppViewModel.swift` 当前持有 `models`、`statusMessages` 和 `pids`，`refreshStatus()` 从 `ModelProcessManager` 读取每个模型状态并更新缓存。
  - `App/Sources/AppDelegate.swift` 当前在 `applicationDidFinishLaunching` 中创建 `MenuBarController`，并通过 `viewModel.apiServer.onModelStateChanged` 回调刷新 `AppViewModel` 状态。
- 2026-07-04 用户确认实现口径：`AppDelegate` 创建 `MenuBarController` 时注入现有 `AppViewModel` 或等价只读菜单数据源；`MenuBarController` 只负责读取模型和状态、构建菜单、菜单打开前触发一次轻量刷新，不直接创建 `ConfigStore`、`ModelProcessManager` 或 `APIServer`。

## 实施方向

1. 让 `MenuBarController` 能读取只读菜单数据源，优先复用 `AppViewModel.models` 和 `AppViewModel.statusMessages`。
2. 菜单打开前触发一次 `refreshStatus()` 或等价轻量刷新，不新增独立定时器。
3. 在构建菜单时将服务列表放在顶部；每个服务菜单项只读，标题包含服务名称，状态通过 `NSMenuItem` 图像或稳定文本符号表达。
4. 状态点对齐主面板 `ModelRow` 配色：running 绿点、starting 黄点、error 红点、stopped 灰点；未知状态默认按 stopped 灰点处理。
5. 服务列表后添加分隔线，再保留 `显示面板` 和 `退出`。
6. 复用已完成的 API 启停 UI 同步机制，确保外部 API 启停后菜单状态不会明显滞后。
7. 补充必要的菜单构建单元测试或轻量装配测试；菜单栏真实交互保留手动验收。

## 验证方式

阶段 1 完成时至少验证：

- 已配置多个服务时，点击菜单栏 icon 后下拉菜单展示全部服务名称。
- 运行中的服务显示绿色状态点。
- 未运行服务显示灰色状态点。
- 点击服务菜单项不启动、停止、重启服务，也不打开详情。
- 通过主面板启动 / 停止服务后，再打开菜单栏下拉菜单，状态点正确更新。
- 通过本地 API 启动 / 停止服务后，再打开菜单栏下拉菜单，状态点正确更新。
- `显示面板` 和 `退出` 仍可使用。

## 完成条件

- 菜单栏下拉菜单能展示全部服务及状态点。
- 运行中服务为绿点，停止或未运行服务为灰点。
- 服务菜单项只读。
- 不引入菜单栏启停等额外行为。
- 构建、相关测试和手动验收通过。
- 完成证据写入本文档，并同步 `docs/PLAN_MAP.md`。

## 风险与回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 菜单项过多导致下拉菜单过长 | 可用性下降 | 阶段 1 只实现完整列表；如服务数量明显增多，再单独评估滚动或分组 | 回退到仅 `显示面板` / `退出` |
| 菜单状态与真实进程状态不同步 | 用户误判服务是否运行 | 菜单打开前轻量刷新，并复用已有状态同步事件 | 保留主面板作为权威状态入口 |
| 状态点样式不符合 macOS 菜单显示限制 | 视觉不稳定 | 优先使用 `NSMenuItem` 图像或稳定文本符号，手动验收实际显示效果 | 改为名称前缀文本状态 |
| 菜单打开前刷新引入额外功耗 | 空闲功耗回归 | 只在菜单打开前刷新一次，不新增定时轮询 | 回退为读取已有 `statusMessages` 缓存 |

## 未决问题

| 问题 | 推荐方案 | 是否阻塞阶段 1 | 状态 |
|---|---|---|---|
| 停止状态是否需要灰点，还是只在运行中显示绿点 | 使用灰点 + 名称，保证所有服务行结构一致 | 否 | 已决 |
| 服务菜单项是否可点击 | 阶段 1 保持只读，不触发启停或打开详情 | 否 | 已决 |
| 菜单状态刷新策略 | 菜单打开前触发一次轻量刷新，平时不新增独立轮询 | 否 | 已决 |
| `MenuBarController` 如何获得服务列表和状态 | 由 `AppDelegate` 注入 `AppViewModel` 或一个只读菜单数据源，避免菜单控制器直接创建业务对象 | 否 | 已决 |

## 阶段 1 完成证据

- `MenuBarController`（`App/Sources/MenuBar/MenuBarController.swift`）已重构：
  - 注入 `AppViewModel`，不直接创建 `ConfigStore`、`ModelProcessManager` 或 `APIServer`。
  - 实现 `NSMenuDelegate`，在 `menuWillOpen` 中调用 `appViewModel.refreshStatus()` 触发一次轻量状态刷新，不新增独立轮询。
  - 从 `appViewModel.models` 和 `appViewModel.statusMessages` 读取服务列表和状态，重建菜单项。
  - 每个服务菜单项 `action: nil`，保持只读。
  - 状态点：running→绿色、starting→黄色、error→红色、stopped→灰色，对齐主面板 `ModelRow` 颜色方案。
  - 服务列表与「显示面板」「退出」之间以分隔线分隔；无服务时不添加分隔线。
- `AppDelegate`（`App/Sources/AppDelegate.swift`）已更新为传入 `appViewModel: viewModel`。
- 新增 `App/Tests/MenuBarControllerTests.swift`，包含 6 个测试：
  - 空配置时菜单仅含显示面板和退出 ✅
  - 有服务配置时菜单展示全部服务名称 ✅
  - 运行中服务显示绿色状态点 ✅
  - 已停止服务显示灰色状态点 ✅
  - 服务菜单项为只读（无 action）✅
  - 显示面板项点击触发 onShowPanel ✅
- 全部 126 个测试通过，无回归。
- 用户于 2026-07-04 确认该需求已完成，用作菜单栏真实交互的手动验收闭环。
- 菜单状态同步策略：
  - 每次打开菜单时通过 `menuWillOpen` → `refreshStatus()` 获取最新状态。
  - API 启停后 `onModelStateChanged` 回调通知 `AppViewModel`，下次打开菜单即可反映最新状态。
  - 主面板启停后 `refreshStatus()` 已更新 `statusMessages`，下次打开菜单即可反映。

## 测试覆盖

- 2026-07-04 运行 `swift test` 通过：126 个测试全部 passed。
- 新增 `MenuBarMenuTests` 覆盖菜单栏服务列表核心行为：
  - 空配置时菜单仅含 `显示面板` 和 `退出`。
  - 有服务配置时展示全部服务名称。
  - 运行中服务显示状态点。
  - 已停止服务显示状态点。
  - 服务菜单项只读、无 action。
  - `显示面板` 菜单项触发 `onShowPanel` 回调。
- 治理检查：`python3 /Users/jafish/.codex/skills/plan-governance/scripts/check_plan_governance.py .` 通过。
