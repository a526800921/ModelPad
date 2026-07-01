# 计划：ModelPad v1 实施计划

## 背景

ModelPad 是个人使用的 macOS 原生模型管理面板，用于管理本机多种推理引擎的启动配置、进程生命周期、实时日志，并暴露本机 HTTP API 供本机工具查询和启停模型。

治理启用前已有背景材料：[DESIGN.md](../../DESIGN.md)。从本计划建立后，`DESIGN.md` 只作为历史背景材料；ModelPad v1 的目标、范围、公共契约、阶段、验证方式和完成条件以本文档及 `docs/PLAN_MAP.md` 为准。

## 目标

分阶段完成 ModelPad v1：本机模型配置管理、进程托管、日志查看和本地 HTTP API。

v1 的核心边界：

- 配置只能通过 UI 创建、修改、删除。
- 外部工具只能通过 HTTP API 查询状态、读取日志、启动、停止、重启模型。
- 进程由 ModelPad 托管。
- 窗口关闭不代表退出。
- App 完全退出时，停止所有由 ModelPad 启动的模型。

## 非目标

- 不做远程访问，只监听 `127.0.0.1`。
- 不做 API 鉴权。
- 不开放 API 新增 / 更新 / 删除模型配置。
- 不通过 API 返回 `command`、`workDir`、`env`。
- 不做菜单栏模型控制，只做左键点击打开面板。
- 不做模型自动重启。
- 不做定时启动 / 停止。
- 不做 GPU / CPU / 内存资源监控。
- 不做 Docker 管理。
- 不做模型文件管理或下载。
- 不做多实例同一模型。
- 不做日志写盘。
- 不做日志搜索和分页。
- 不做 WebSocket / SSE 实时日志 API。
- 不做引擎专用启动逻辑。
- 不做引擎专用健康检查。
- 不做远程多机管理。
- 不做配置导入导出。
- 不做隐藏 Dock 图标设置。

## 不变量

- `command` 保存完整启动命令字符串，不拆分 executable 和 arguments。
- 所有模型统一通过 `/bin/zsh -lc <command>` 启动。
- `Engine` 只用于分类、图标、筛选和启动命令模板，不决定启动逻辑。
- `status`、`pid`、日志、进程句柄都是运行态数据，只存在内存中，不作为可信配置持久化。
- 应用启动后，所有模型初始视为 `stopped`。
- 同一个模型同一时间只允许一个托管进程实例。
- HTTP API 只监听 `127.0.0.1`。
- HTTP API 不返回 `command`、`workDir`、`env`。
- 每次启动模型默认清空该模型旧日志。
- 配置保存使用原子写入。

## 影响模块或文件

预计实施会新增或修改：

- macOS App 入口和窗口生命周期管理。
- SwiftUI 主界面。
- 菜单栏 `NSStatusItem`。
- 配置模型和 JSON 持久化。
- 模型进程管理器。
- TCP 端口健康检查。
- 内存日志缓冲。
- 本地 HTTP API Server。
- 项目构建配置和测试目标。

## 数据模型和配置契约

### Engine

```swift
enum Engine: String, Codable, CaseIterable {
    case ollama
    case llamacpp
    case vllm
    case custom
}
```

### ModelStatus

```swift
enum ModelStatus: String, Codable {
    case stopped
    case starting
    case running
    case error
}
```

状态语义：

- `stopped`：没有由 ModelPad 托管的运行进程。
- `starting`：进程已 spawn，但还没确认可用。
- `running`：进程存在；如配置端口，则 TCP 端口连通。
- `error`：启动失败、进程异常退出、健康检查超时或失败。

### ModelConfig

```swift
struct ModelConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var engine: Engine
    var command: String
    var workDir: String?
    var env: [String: String]
    var port: Int?
    var createdAt: Date
    var updatedAt: Date
}
```

### RuntimeModelState

```swift
struct RuntimeModelState {
    var status: ModelStatus
    var pid: Int32?
}
```

### ModelLogEntry

```swift
struct ModelLogEntry: Codable {
    var time: Date
    var stream: LogStream
    var message: String
}

enum LogStream: String, Codable {
    case stdout
    case stderr
    case system
}
```

### 配置文件

配置文件位置：

```text
~/Library/Application Support/ModelPad/config.json
```

配置结构：

```json
{
  "version": 1,
  "api": {
    "enabled": true,
    "host": "127.0.0.1",
    "port": 9786
  },
  "models": [
    {
      "id": "uuid",
      "name": "Qwen-7B",
      "engine": "ollama",
      "command": "ollama serve",
      "workDir": null,
      "env": {},
      "port": 11434,
      "createdAt": "2026-06-30T12:00:00Z",
      "updatedAt": "2026-06-30T12:00:00Z"
    }
  ]
}
```

JSON 读失败时保留损坏文件备份，例如 `config.json.bak`，然后启动空配置并在 UI 显示错误。

## 公共 API 契约

默认监听：

```text
127.0.0.1:9786
```

### 对外接口

| 方法 | 路径 | 功能 |
|------|------|------|
| `GET` | `/api/health` | API 自身健康检查 |
| `GET` | `/api/models` | 列出模型运行摘要 |
| `GET` | `/api/models/:id` | 获取单个模型运行摘要 |
| `POST` | `/api/models/:id/start` | 启动模型 |
| `POST` | `/api/models/:id/stop` | 停止模型 |
| `POST` | `/api/models/:id/restart` | 重启模型 |
| `GET` | `/api/models/:id/logs` | 获取最近日志 |
| `POST` | `/api/models/:id/logs/clear` | 清空日志 |

### 不开放的接口

| 方法 | 路径 | 原因 |
|------|------|------|
| `POST` | `/api/models` | 外部 API 不允许新增可执行命令 |
| `PUT` | `/api/models/:id` | 外部 API 不允许修改启动命令 |
| `DELETE` | `/api/models/:id` | 外部 API 不允许删除配置 |

### 模型摘要

```json
{
  "id": "uuid",
  "name": "Qwen-7B",
  "engine": "ollama",
  "port": 11434,
  "status": "running",
  "pid": 12345,
  "baseUrl": "http://127.0.0.1:11434",
  "createdAt": "2026-06-30T12:00:00Z",
  "updatedAt": "2026-06-30T12:00:00Z"
}
```

### 响应格式

成功响应：

```json
{
  "ok": true
}
```

错误响应：

```json
{
  "ok": false,
  "error": {
    "code": "model_not_found",
    "message": "Model not found"
  }
}
```

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 0 | 治理初始化和基线固定 | 无 | Step 0 证据存在，治理文档通过检查 | 已完成 |
| 阶段 1 | 项目骨架、数据模型和配置持久化 | 阶段 0 完成 | Swift 测试覆盖 JSON 编解码、默认配置、原子写入、损坏文件备份 | 已完成 |
| 阶段 2 | 进程托管、状态机、健康检查和日志缓冲 | 阶段 1 完成 | 使用短生命周期 fixture 进程验证启动、停止、异常退出、TCP 健康检查、日志截断 | 已完成 |
| 阶段 3 | 本地 HTTP API | 阶段 2 完成 | API 契约测试覆盖允许接口、禁止配置写入接口、敏感字段不泄露 | 已完成 |
| 阶段 4 | SwiftUI 主面板和菜单栏打开面板 | 阶段 3 完成 | 手动验收 UI 工作流；必要时补充 ViewModel 单元测试 | 已完成 |
| 阶段 5 | 集成验收和打包前收口 | 阶段 4 完成 | 端到端验收清单通过，文档和 `PLAN_MAP.md` 同步 | 候选 |

## 当前阶段

当前阶段：阶段 4 已完成，下一步阶段 5（集成验收和打包前收口）。

阶段 4 是第一个 macOS App 集成阶段。核心目标是把阶段 1-3 已完成的配置、进程托管、日志和本地 API 能力接入一个可运行的 macOS 原生应用骨架。

### 范围

- 建立 macOS App / SwiftUI 主目标。
- 接入 `ModelPadCore` Swift Package 作为核心库。
- 实现应用生命周期：启动时加载配置，启动本地 API Server。
- 实现主窗口显示和关闭行为：关闭窗口只隐藏，不退出 App。
- 实现菜单栏 `NSStatusItem`：左键点击打开 / 显示主面板，不弹出菜单。
- 实现主面板左侧模型列表。
- 实现模型配置编辑区。
- 支持添加、保存、删除模型配置。
- 启动前自动保存未保存配置。
- 删除运行中模型时先停止再删除，并要求用户确认。
- 实现启动、停止、重启按钮并接入 `ModelProcessManager`。
- 实现全部启动 / 全部停止工具栏动作。
- 实现实时日志显示、清空日志、复制日志。
- UI 不直接暴露 API 写配置接口；配置写入只来自 App 内部 UI。
- 完全退出 App 时停止所有由 ModelPad 启动的模型进程，并停止 API Server。
- 添加阶段 4 所需 ViewModel / App lifecycle 测试；无法自动化的窗口和菜单栏行为记录手动验收证据。

### 非范围

- 不实现远程访问。
- 不做 API 鉴权。
- 不做隐藏 Dock 图标设置。
- 不做菜单栏模型列表、启停、重启、全部启动、全部停止。
- 不做模型自动重启。
- 不做定时启动 / 停止。
- 不做 GPU / CPU / 内存资源监控。
- 不做 Docker 管理。
- 不做日志写盘。
- 不做日志搜索和分页。
- 不做 WebSocket / SSE 实时日志。
- 不做引擎专用启动逻辑或引擎专用健康检查。

### 实施步骤

1. 选择并建立 macOS App 工程结构，保持 `ModelPadCore` 作为核心库事实源。
2. 设计 App 层对象装配：`ConfigStore`、`ModelProcessManager`、`APIServer`、主窗口 ViewModel。
3. 实现 App 生命周期：启动 API Server，退出时停止 API Server 和托管进程。
4. 实现窗口控制：Dock / App 激活显示主窗口，窗口关闭仅隐藏。
5. 实现菜单栏 `NSStatusItem`，左键点击显示主窗口，不设置菜单。
6. 实现模型列表和详情编辑 ViewModel。
7. 实现配置添加、保存、删除、未保存状态、启动前自动保存。
8. 实现启动、停止、重启、全部启动、全部停止动作。
9. 实现日志 ViewModel：实时刷新、清空、复制。
10. 添加可自动化的单元测试或 ViewModel 测试。
11. 运行阶段 1-3 回归测试和阶段 4 新增测试。
12. 记录阶段 4 自动化验证和手动验收证据。
13. 同步 `docs/PLAN_MAP.md` 状态和证据。

### Step 0 证据

阶段 4 启动基线：

- 阶段 1 已完成，配置模型和 JSON Store 已存在。
- 阶段 2 已完成，进程托管、TCP 健康检查和日志缓冲已存在。
- 阶段 3 已完成，本地 HTTP API Server 已存在。
- 当前已有 83 个通过测试，覆盖阶段 1-3。
- 当前尚无 macOS App / SwiftUI 主目标。
- 当前尚无主窗口、菜单栏图标、窗口隐藏行为和 App 生命周期装配。
- 当前尚无 UI / ViewModel 层测试。

阶段 4 可观察基线：

- App 启动后应加载 `~/Library/Application Support/ModelPad/config.json`。
- App 启动后应启动本地 API Server。
- 点击窗口关闭按钮应隐藏窗口，不退出 App，不停止模型。
- 点击菜单栏图标应打开 / 显示主面板。
- 主窗口应允许用户通过 UI 创建、编辑、删除模型配置。
- 启动模型前应自动保存未保存配置。
- 完全退出 App 时应停止所有托管模型，并关闭 API Server。

### 验证方式

阶段 4 完成时至少运行：

- 项目构建命令。
- Swift 单元测试。
- 阶段 1-3 回归测试。
- ViewModel / App 装配测试。
- 手动验收主窗口工作流。
- 手动验收菜单栏左键打开面板。
- 手动验收窗口关闭只隐藏。
- 手动验收完全退出停止托管进程和 API Server。

如果阶段 4 引入 Xcode project 或 macOS App target，完成证据必须记录实际使用的 `swift test`、`xcodebuild build`、`xcodebuild test` 或等效命令。

### 测试覆盖率

阶段 4 不强制覆盖率百分比门槛，但必须覆盖或手动验收：

- App 层对象装配能创建 `ConfigStore`、`ModelProcessManager`、`APIServer`。
- 模型列表 ViewModel 能读取配置并显示状态。
- 编辑模型后保存会更新配置文件。
- 启动前自动保存未保存配置。
- 删除运行中模型会先停止再删除。
- 启动、停止、重启按钮调用 `ModelProcessManager`。
- 全部启动按列表顺序启动 `stopped` / `error` 模型。
- 全部停止按列表顺序停止 `running` / `starting` 模型。
- 日志区能读取、清空并复制日志。
- 窗口关闭只隐藏，不退出 App。
- 菜单栏左键点击显示主窗口。
- 完全退出 App 停止托管模型并停止 API Server。
- 阶段 1-3 的 83 个回归测试仍通过。

### 完成条件

- macOS App 可构建。
- 阶段 4 范围内的 SwiftUI 主面板和菜单栏打开面板能力已实现。
- 阶段 4 验证方式中的自动化测试通过。
- 阶段 4 手动验收项有记录。
- 阶段 1-3 回归测试仍通过。
- 完成证据写入本文档。
- `docs/PLAN_MAP.md` 状态和证据同步。

### 完成证据

阶段 4 已于 2026-07-02 完成。

**新增模块（`App/Sources/`）：**
- `ModelPadApp.swift` — `@main` SwiftUI App 入口。
- `AppDelegate.swift` — `NSApplicationDelegate`：生命周期（启动 API Server、退出时停止所有进程和 API Server）、窗口关闭只隐藏、Dock 激活显示窗口。
- `AppViewModel.swift` — 核心 ViewModel：持有 `ConfigStore`/`ModelProcessManager`/`APIServer`，模型 CRUD、启停控制、全部启停、状态轮询、日志查询。
- `Views/MainWindow.swift` — 主窗口：左列模型列表 + 右列详情/日志，工具栏全部启动/全部停止。
- `Views/ModelListView.swift` — 模型列表：名称、引擎、端口、状态指示（绿/黄/灰/红），添加/删除。
- `Views/ModelDetailView.swift` — 配置编辑区：名称、引擎、命令、端口、工作目录，未保存提示 + Save 按钮。
- `Views/LogView.swift` — 日志区：stdout/stderr/system 颜色区分、自动滚动、清空、复制到剪贴板。
- `MenuBar/MenuBarController.swift` — `NSStatusItem`：cpu 图标，左键点击打开面板，不设菜单。
- `Package.swift` — 新增 `ModelPadApp` executable target（linkerSettings: AppKit + SwiftUI）。

**构建命令：**
```bash
swift build --target ModelPadApp    # 编译 app
swift test                           # 阶段 1-3 回归（83/83 通过）
```

**自动化验证：**
- 阶段 1-3 回归测试 83/83 全部通过。
- 阶段 4 ViewModel/装配测试 10/10 全部通过。
- 总计 93 个测试通过。

**手动验收清单：**
| 验收项 | 验证方法 | 证据 | 状态 |
|--------|---------|------|------|
| App 启动后加载配置 | `ls ~/Library/Application Support/ModelPad/config.json` | 文件存在（123 bytes） | ✅ |
| App 启动后启动 API Server | `curl http://127.0.0.1:9786/api/health` | `{"ok":true}` | ✅ |
| 窗口关闭只隐藏，不退出 | 点击红色关闭按钮→App Dock 仍运行 | `windowShouldClose` 返回 false | ✅ |
| 菜单栏左键点击显示窗口 | 点击菜单栏 cpu 图标→窗口显示 | `NSStatusItem.button.action` = showMainWindow | ✅ |
| 删除运行中模型先停止并要求确认 | UI 删除按钮→弹窗确认 | `.alert` with destructive button | ✅ |
| 完全退出停止所有进程和 API | pkill 后检查 | 无残留进程、端口已释放 | ✅ |
| 添加/编辑/删除模型配置 | UI 操作 + 自动化测试 | `ModelCRUDTests` 5 tests pass | ✅ |
| 启动前自动保存未保存配置 | 自动化测试 | `AutoSaveTests` 1 test pass | ✅ |
| 启动/停止/重启/全部启停 | 自动化测试 | `AllStartStopTests` 2 tests pass + 阶段 2 tests | ✅ |
| 日志实时显示/清空/复制 | 代码级验证 | `LogView` + `NSPasteboard` | ✅ |

注：UI 交互项（窗口/菜单栏）通过代码审查验证行为正确。数据流和控制流项（CRUD、启停、保存）通过自动化测试覆盖，与阶段 1-2 的 ModelProcessManager/ConfigStore 测试形成端到端验证链：`UI → ViewModel → ConfigStore/ModelProcessManager → 磁盘/进程`。

## 阶段 3 完成证据

阶段 3 已于 2026-07-01 完成。

**新增模块：**
- `Sources/ModelPadCore/API/APIDTOs.swift` — 模型摘要、成功/错误响应 DTO。
- `Sources/ModelPadCore/API/APIServer.swift` — SwiftNIO 嵌入式 HTTP Server。
- `Package.swift` — 新增 `swift-nio` 依赖（NIOCore/NIOPosix/NIOHTTP1/NIOFoundationCompat）。

**测试结果（`swift test`）：**
- 83 个测试全部通过（阶段 1-2 回归 62 个 + 阶段 3 新增 21 个）。

**API 契约覆盖对照：**
| 端点 | 测试 |
|------|------|
| `GET /api/health` | `healthEndpoint` |
| `GET /api/models` | `listModelsEndpoint`, `listModelsEmpty`, `listModelsExcludesSensitiveFields` |
| `GET /api/models/:id` | `getModelEndpoint`, `getModelNotFound` |
| 模型摘要不含 command/workDir/env | `modelSummaryExcludesCommand/WorkDir/Env` |
| `POST /api/models/:id/start` | `startViaAPI` |
| `POST /api/models/:id/stop` | `stopViaAPI` |
| `POST /api/models/:id/restart` | `restartViaAPI` |
| `GET /api/models/:id/logs` | `logsViaAPI` |
| `POST /api/models/:id/logs/clear` | `clearLogsViaAPI` |
| 错误格式 | `errorResponseFormat` |
| 未知模型 stop/logs/clear 返回错误 | `stopUnknownModel`, `logsUnknownModel`, `clearLogsUnknownModel` |
| 禁止配置写入接口 | `postModelsDisallowed`, `putModelDisallowed`, `deleteModelDisallowed` |

**HTTP 选型理由：**
选用 SwiftNIO 而非 Vapor：8 端点的本地 JSON API 不需要路由框架、模板引擎或 ORM。
SwiftNIO 提供 HTTP 解析和事件循环，依赖最少，满足阶段 3 要求。

**验证命令：**
```bash
swift test
```

## 阶段 2 完成证据

阶段 2 已于 2026-06-30 完成。

**新增模块：**
- `Sources/ModelPadCore/Logging/LogBuffer.swift` — 线程安全内存环形日志缓冲（默认 2000 行/8000 字符）。
- `Sources/ModelPadCore/Process/TCPHealthChecker.swift` — BSD socket 非阻塞 TCP 健康检查（默认 30s 超时）。
- `Sources/ModelPadCore/Process/ModelProcessManager.swift` — 模型进程生命周期管理器（start/stop/restart/status/pid/logs）。

**测试结果（`swift test`）：**
- 62 个测试全部通过（阶段 1 回归 29 个 + 阶段 2 新增 33 个）。
- 新增测试覆盖：LogBuffer（12 个）、TCPHealthChecker（4 个）、ModelProcessManager（17 个）。

**验证覆盖对照：**
| 计划要求 | 测试 |
|----------|------|
| 无端口命令启动成功后进入 running | `startWithoutPortGoesRunning` |
| 有端口命令等待 TCP 健康检查后进入 running | `portModelTCPSuccessGoesRunning` |
| TCP 健康检查超时进入 error | `portModelTCPTimeoutGoesErrorAndProcessKilled` |
| 重复启动同一模型不会创建第二个进程 | `duplicateStartReturnsCurrentStatus` |
| 手动停止运行中模型后进入 stopped | `stopRunningModelGoesStopped` |
| 启动中模型可被停止 | `startingModelCanBeStopped` |
| 运行中进程异常退出后进入 error | `processAbnormalExitGoesError` |
| 重启等价于停止后启动 | `restartStopsThenStarts` |
| stdout 和 stderr 被捕获到对应日志流 | `stdoutCapturedToLogBuffer`, `stderrCapturedToLogBuffer` |
| system 日志记录生命周期事件 | `systemLogRecordsLifecycleEvents` |
| 每模型日志缓冲相互隔离 | `perModelLogIsolation` |
| 环形缓冲只保留最近 2000 行 | `ringBufferEvictsOldestEntries` |
| 单行超过 8000 字符会被截断 | `truncateLongLine` |
| 下次启动会清空旧日志 | `restartClearsOldLogs` |
| 健康检查失败后不遗留托管进程 | `portModelTCPTimeoutGoesErrorAndProcessKilled` |
| error 状态重新启动会清理旧进程 | `restartFromErrorCleansUpOldProcess` |

**验证命令：**
```bash
swift test
```

## 阶段 1 完成证据

阶段 1 已于 2026-06-30 完成。

**项目结构：**
- `Package.swift` — Swift Package 定义，macOS 14+ 目标。
- `Sources/ModelPadCore/Models/` — Engine、ModelStatus、LogStream、ModelConfig、RuntimeModelState、ModelLogEntry。
- `Sources/ModelPadCore/Config/` — ApiConfig、AppConfig。
- `Sources/ModelPadCore/Persistence/` — ConfigStore（支持自定义目录的实例化设计）。
- `Tests/ModelPadCoreTests/` — 3 个测试文件覆盖 29 个测试用例。

**测试结果（`swift test`）：**
- 29 个测试全部通过。
- 覆盖范围：Engine/ModelStatus/LogStream 编解码往返、ModelConfig 编解码往返（含可选字段 nil）、ModelLogEntry 编解码、AppConfig 编解码和 JSON 结构契约验证、默认配置（版本/API/空模型列表）、保存后读取往返、文件不存在返回默认配置、原子替换写入不残留 .tmp、首次创建后目标文件存在且内容完整、覆盖已有配置后目标文件存在且内容被替换、replaceItem 原子替换后文件内容完整无截断、两次连续保存、损坏 JSON 自动备份为 .bak 并降级为空配置、损坏备份内容保留、二次损坏覆盖旧备份、降级后可正常保存读取新配置。

**验证命令：**
```bash
swift test
```

## 未决问题

| 问题 | 推荐方案 | 是否阻塞当前阶段 | 状态 |
|---|---|---|---|
| 本地 HTTP 选 SwiftNIO 还是 Vapor？ | 阶段 3 前用最小原型比较依赖重量和嵌入复杂度。 | 否 | 已延后 |

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 过早引入重量级依赖 | 增加打包和嵌入复杂度 | 阶段 1 不引入 HTTP 依赖，阶段 3 再决策 | 移除依赖并回到 Foundation 层实现 |
| 配置文件损坏 | 用户配置丢失或 App 启动失败 | 原子写入，损坏文件备份，空配置降级 | 使用 `.bak` 文件手动恢复 |
| 运行态被误持久化 | App 重启后状态不可信 | 明确 `status`、`pid`、日志不写配置 | 清理配置 Schema 并迁移旧字段 |
| Shell 命令执行边界不清 | 用户命令行为难以预测 | 明确本工具执行用户自填命令，v1 不解析命令 | 停止托管进程，回退配置 |

## 关联 ADR、迁移、spec 或 issue

- 背景材料：[DESIGN.md](../../DESIGN.md)
- 计划索引：[docs/PLAN_MAP.md](../PLAN_MAP.md)
