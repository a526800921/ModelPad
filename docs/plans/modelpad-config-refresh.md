# 计划：ModelPad 配置刷新

## 目标

在左侧模型列表底部的“新增”按钮旁增加“刷新”按钮，并新增一个本地 HTTP 刷新接口，使用户或自动化流程在手动编辑 `config.json` 后，可以让运行中的 ModelPad 重新读取配置并更新面板内缓存。

## 背景

用户于 2026-07-04 提出需求：有时会直接在 `config.json` 中增加模型，而不是通过面板新增。当前 App 启动时会读取配置并缓存在 `AppViewModel.models`，导致面板左侧列表不会自动显示手动加入的模型。

现状快照：

- `App/Sources/AppViewModel.swift` 已有 `reloadModels()`，会从 `ConfigStore.load()` 读取配置并更新 `models`，但当前没有面板入口或 API 入口触发它。
- `App/Sources/Views/ModelListView.swift` 左侧列表底部当前有“添加”和“删除”按钮，尚无刷新按钮。
- `Sources/ModelPadCore/API/APIServer.swift` 的 `GET /api/models` 和按 ID 查询会直接读取 `ConfigStore`，但 API 启停后的 UI 同步只通过 `onModelStateChanged` 做状态刷新，不会让 `AppViewModel.models` 重新读取配置。
- v1 设计要求外部 API 不开放新增、更新、删除模型配置；本需求只允许重新读取已有配置文件，不通过 API 修改配置。

## 范围

- 在左侧模型列表底部“新增”按钮旁增加刷新按钮。
- 刷新按钮触发重新读取 `ConfigStore` 中的 `config.json`，更新 `AppViewModel.models`。
- 新增本地 HTTP API，用于自动化触发同样的配置刷新。
- 刷新后同步模型列表、选中项、编辑态和运行状态展示。
- 刷新只读取持久化配置，不启动、停止、重启任何模型进程。
- 增加 ViewModel、API 契约和必要 UI 测试。

## 非范围

- 不开放 API 新增、修改、删除模型配置。
- 不监听 `config.json` 文件变化，不做自动文件监控。
- 不在刷新时自动启动新加入的模型。
- 不在刷新时自动停止从配置中删除的模型。
- 不改变 `config.json` 的 Schema。
- 不新增鉴权、远程访问或局域网监听。

## 公共 API 契约

### 刷新配置

接口：

```http
POST /api/config/reload
```

语义：

1. 重新读取 `~/Library/Application Support/ModelPad/config.json`。
2. 读取成功后更新 App 内存中的模型列表缓存。
3. 返回刷新后的模型摘要列表。
4. 不修改 `config.json`。
5. 不启停任何模型进程。

建议响应：

```json
{
  "ok": true,
  "models": [
    {
      "id": "UUID",
      "name": "model name",
      "engine": "custom",
      "status": "stopped",
      "pid": null,
      "port": 8000,
      "baseUrl": "http://127.0.0.1:8000",
      "createdAt": "2026-07-04T00:00:00Z",
      "updatedAt": "2026-07-04T00:00:00Z"
    }
  ]
}
```

错误处理：

| 场景 | 建议错误码 | HTTP 状态 | 说明 |
|---|---|---:|---|
| `config.json` 不是合法 JSON 或无法解码 | `config_reload_failed` | 400 | 不更新当前内存模型列表，保留刷新前状态 |
| 配置文件不存在 | - | 200 | 沿用 `ConfigStore.load()` 当前语义，视为默认空配置 |
| 非本接口路径 | `not_found` | 400 | 沿用现有路由行为 |

路由选择说明：

- 使用 `POST /api/config/reload`，因为该接口会改变 App 内存状态，语义上不是纯查询。
- 不使用 `POST /api/models`，避免与“外部 API 不允许新增模型配置”的既有边界冲突。

## UI 契约

- 刷新按钮放在左侧模型列表底部，“添加”按钮右侧。
- 使用 `arrow.clockwise` 系统图标，`.help("重新读取配置")`。
- 按钮只触发配置重载，不保存未保存编辑内容。
- 如果当前存在未保存编辑内容，应优先复用现有 `selectModel` 的保存策略：刷新前保存当前编辑模型，避免用户在 UI 中正在编辑的配置被静默丢弃。
- 刷新成功后：
  - 当前选中模型仍存在时保持选中，并同步 `editingModel` 到新配置。
  - 当前选中模型已不存在时，选中新列表第一个模型；列表为空则清空选中和编辑态。
  - `hasUnsavedChanges` 置为 `false`。
  - 调用 `refreshStatus()` 更新状态和 pid。
- 刷新失败时：
  - 保留刷新前的模型列表、选中项和编辑态。
  - 后续实现可先记录错误日志或在控制台输出；如需 UI 错误提示，另开计划。

## 运行态规则

- 配置刷新不改变 `ModelProcessManager` 中已有运行上下文。
- 新增到 `config.json` 的模型刷新后出现在列表中，初始状态按 `processManager.status(for:)` 计算，通常为 `stopped`。
- 已存在且正在运行的模型，如果刷新后仍保留相同 `id`，继续显示其当前运行状态和 pid。
- 如果某个运行中模型从 `config.json` 删除，刷新后不再显示在模型列表；本阶段不自动停止它，避免配置编辑失误导致进程被意外终止。该边界应在文档和测试中固定。

## Step 0 证据

- `AppViewModel.reloadModels()` 当前可作为 UI 刷新基础，但选择状态和未保存编辑处理需要补强。
- `ModelListView` 底部按钮区域当前只包含添加按钮、Spacer 和删除按钮。
- `APIServer` 当前没有 `/api/config/reload` 路由，也没有面向 UI 的“配置已重载”回调。
- `APIServer.handleListModels()` 已能从 `ConfigStore.load()` 获取最新配置，可复用模型摘要组装逻辑。
- `DESIGN.md` 既有 API 边界要求不开放新增、更新、删除配置；刷新接口必须保持只读配置文件语义。

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | 面板刷新按钮和本地刷新接口 | 用户明确批准开始非文档实现 | ViewModel、API 契约和 UI 测试通过；手动编辑 config 后可刷新显示 | ✅ 已完成 |

## 实施方向

1. 调整 `AppViewModel.reloadModels()`，使其在重新读取配置时处理未保存编辑、选中项保留、选中项缺失和状态刷新。
2. 在 `ModelListView` 的底部按钮区，将刷新按钮放在添加按钮旁边，触发 `viewModel.reloadModels()`。
3. 为 `APIServer` 增加配置重载回调，例如 `onConfigReloadRequested`，由 App 层绑定到 `AppViewModel.reloadModels()`。
4. 在 API 层新增 `POST /api/config/reload` 路由；成功时返回刷新后的模型摘要列表，失败时返回 `config_reload_failed`。
5. 抽取或复用模型摘要构造逻辑，避免 `GET /api/models` 与刷新接口响应漂移。
6. 增加测试覆盖刷新按钮触发 ViewModel 重载、API 成功刷新、解码失败保留旧缓存、刷新不启停进程。

## 验证方式

阶段 1 完成时至少验证：

- 启动 App 后，手动向 `config.json` 增加模型，点击左侧列表底部刷新按钮后新模型显示。
- 调用 `POST /api/config/reload` 后，面板模型列表同步显示新模型。
- 当前选中模型仍存在时，刷新后仍保持选中。
- 当前选中模型被从配置中删除时，刷新后选择第一个模型或清空选中。
- 刷新不会启动、停止或重启任何模型。
- 配置损坏时刷新失败，并保留刷新前列表。
- `GET /api/models`、`POST /api/models/:id/start` 等既有 API 回归通过。
- `swift test` 通过。

## 完成条件

- UI 刷新按钮和本地刷新接口均已实现。
- 手动编辑 `config.json` 后可通过 UI 和 API 两种方式刷新模型列表。
- 刷新失败保留旧内存状态，不破坏正在运行的模型。
- 新增和回归测试通过。
- 完成证据写入本文档，并同步 `docs/PLAN_MAP.md`。

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 手动编辑配置时 JSON 损坏 | 刷新失败 | 失败时保留旧缓存，返回 `config_reload_failed` | 修复 `config.json` 后再次刷新 |
| 刷新覆盖 UI 未保存编辑 | 用户编辑内容丢失 | 刷新前沿用当前保存策略，或实现前确认更严格交互 | 暂时移除刷新按钮，仅保留 API |
| 删除运行中模型后刷新 | 列表不再显示但进程仍运行 | 文档固定“不自动停止”；后续可增加运行孤儿提示 | 通过旧配置恢复模型 ID 后再停止，或退出 App 清理托管进程 |

## 未决问题

| 问题 | 推荐方案 | 是否阻塞当前阶段 | 状态 |
|---|---|---|---|
| 刷新失败是否需要 UI 弹窗提示 | 阶段 1 先不做弹窗，避免扩大 UI 状态；可记录错误并通过后续计划补充 | 否 | 待确认 |
| API 响应是否必须返回完整模型列表 | 建议返回，与自动化调用方更友好；也可仅返回 `ok` 后调用 `GET /api/models` | 否 | ✅ 已确认：返回完整模型列表 |

## 阶段 1 完成证据

**实施日期：** 2026-07-04

### 变更文件

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `App/Sources/AppViewModel.swift` | 增强 | `reloadModels()` 增加保存→验证→重载→选区恢复完整流程 |
| `App/Sources/Views/ModelListView.swift` | 新增 UI | "添加"按钮旁增加 `arrow.clockwise` 刷新按钮 |
| `App/Sources/AppDelegate.swift` | 连线 | 绑定 `onConfigReloadRequested` → `reloadModels()` |
| `Sources/ModelPadCore/API/APIServer.swift` | 新增 API | `onConfigReloadRequested` 回调 + `POST /api/config/reload` 路由 + `buildModelSummaries` 复用 |
| `App/Tests/AppViewModelTests.swift` | 新增测试 | `ConfigReloadTests` 套件（10 个测试） |
| `Tests/ModelPadCoreTests/APITests/APIContractTests.swift` | 新增测试 | `POST /api/config/reload` 契约测试（9 个测试） |

### 测试结果

```
swift test → 145 tests in 9 suites passed, 0 failures
```

覆盖：
- ✅ ViewModel reloadModels 从磁盘读取新模型
- ✅ reloadModels 刷新前自动保存未保存编辑
- ✅ 选中模型仍存在时保持选中 + editingModel 同步
- ✅ 选中模型已删除时 fallback 到第一个
- ✅ 列表为空时清空选中和编辑态
- ✅ 刷新不启动任何模型
- ✅ 刷新不停止运行中模型
- ✅ 配置损坏时保留旧列表和选中项
- ✅ 存在未保存编辑时先保存再刷新
- ✅ hasUnsavedChanges 刷新后置 false
- ✅ 从配置删除的模型刷新后不在列表显示
- ✅ POST /api/config/reload 200 + 模型列表
- ✅ POST /api/config/reload 空配置 200 + 空数组
- ✅ POST /api/config/reload 损坏配置 400 + config_reload_failed
- ✅ reload 不修改磁盘配置
- ✅ reload 不启停任何模型进程
- ✅ reload 响应不暴露 command/workDir/env
- ✅ reload 后 GET /api/models 与 reload 响应一致
- ✅ reload 后 GET /api/health 仍正常（既有 API 回归）
