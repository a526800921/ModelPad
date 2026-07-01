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
| 阶段 3 | 本地 HTTP API | 阶段 2 完成 | API 契约测试覆盖允许接口、禁止配置写入接口、敏感字段不泄露 | 实施中 |
| 阶段 4 | SwiftUI 主面板和菜单栏打开面板 | 阶段 3 完成 | 手动验收 UI 工作流；必要时补充 ViewModel 单元测试 | 候选 |
| 阶段 5 | 集成验收和打包前收口 | 阶段 4 完成 | 端到端验收清单通过，文档和 `PLAN_MAP.md` 同步 | 候选 |

## 当前阶段

当前阶段：阶段 3，本地 HTTP API。

阶段 1 项目结构决策：优先建立 Swift Package 承载核心模型、配置持久化和单元测试；SwiftUI App/Xcode 目标在阶段 4 补齐。这样阶段 1 可以先获得可运行测试和清晰的核心模块边界。

### 范围

- 实现本地 HTTP API Server，只监听 `127.0.0.1`。
- 默认端口使用配置契约中的 `9786`。
- 对外接口以本文档“公共 API 契约”为准。
- 接入阶段 1 的 `AppConfig` / `ModelConfig` 作为模型配置来源。
- 接入阶段 2 的 `ModelProcessManager` 作为启动、停止、重启、状态、pid、日志来源。
- 实现模型运行摘要响应，不返回 `command`、`workDir`、`env`。
- 实现统一 JSON 成功响应和错误响应。
- 实现 `GET /api/health`。
- 实现 `GET /api/models` 和 `GET /api/models/:id`。
- 实现 `POST /api/models/:id/start`、`stop`、`restart`。
- 实现 `GET /api/models/:id/logs`。
- 实现 `POST /api/models/:id/logs/clear`。
- 明确拒绝或不注册配置写入接口：`POST /api/models`、`PUT /api/models/:id`、`DELETE /api/models/:id`。
- 添加阶段 3 所需 API 契约测试。

### 非范围

- 不实现完整 SwiftUI 主界面。
- 不实现菜单栏图标。
- 不实现远程访问。
- 不做 API 鉴权。
- 不做 HTTPS。
- 不做配置写入 API。
- 不做 WebSocket / SSE 实时日志。
- 不做日志分页和搜索。
- 不实现模型自动重启。
- 不实现日志写盘。
- 不修改配置文件 Schema，除非发现阶段 3 无法在现有契约下实现。

### 实施步骤

1. 选择并记录阶段 3 HTTP 实现方式：优先最小嵌入式 HTTP 实现，避免阶段 3 引入过重依赖；如引入 SwiftNIO 或 Vapor，需补充理由。
2. 定义 API 响应 DTO：模型摘要、日志条目、成功响应、错误响应。
3. 实现 API Server 的路由、请求解析和 JSON 编码。
4. 实现模型配置只读仓库或注入接口，供 API 查询模型列表和详情。
5. 接入 `ModelProcessManager` 完成 start / stop / restart / logs / clear。
6. 添加 API 契约测试，包括允许接口、禁止接口、错误响应和敏感字段不泄露。
7. 运行阶段 1-2 回归测试和阶段 3 新增测试。
8. 记录阶段 3 完成证据。
9. 同步 `docs/PLAN_MAP.md` 状态和证据。

### Step 0 证据

阶段 3 启动基线：

- 阶段 1 已完成，当前 Swift Package 可构建，配置模型和 JSON Store 已存在。
- 阶段 2 已完成，`LogBuffer`、`TCPHealthChecker`、`ModelProcessManager` 已存在。
- 当前已有 62 个通过测试，覆盖阶段 1-2。
- 当前尚无本地 HTTP API Server。
- 当前尚无 API 路由、响应 DTO 或契约测试。
- 当前公共 API 契约已在本文档“公共 API 契约”定义。

阶段 3 可观察基线：

- API 默认监听 `127.0.0.1:9786`。
- API 不做鉴权。
- API 不开放配置新增、更新、删除。
- API 模型摘要不得包含 `command`、`workDir`、`env`。
- API 错误响应必须使用统一 JSON 格式。
- API 的 start / stop / restart 行为必须透传阶段 2 的进程托管状态。

### 验证方式

阶段 3 完成时至少运行：

- 项目构建命令。
- Swift 单元测试。
- 阶段 1-2 回归测试。
- API 契约测试。
- API 禁止配置写入接口测试。
- API 敏感字段不泄露测试。
- API 生命周期控制测试。

如果项目脚本尚未建立，阶段 3 需要在完成记录中写明实际使用的 `swift test`、`xcodebuild test` 或等效命令。

### 测试覆盖率

阶段 3 不强制覆盖率百分比门槛，但必须覆盖：

- `GET /api/health` 返回成功。
- `GET /api/models` 返回模型摘要列表。
- `GET /api/models/:id` 返回单个模型摘要。
- 未知模型返回统一 `model_not_found` 错误。
- 模型摘要不包含 `command`、`workDir`、`env`。
- `POST /api/models/:id/start` 启动模型并返回状态 / pid。
- `POST /api/models/:id/stop` 停止模型并返回 `stopped`。
- `POST /api/models/:id/restart` 等价于停止后启动。
- `GET /api/models/:id/logs` 返回日志数组。
- `POST /api/models/:id/logs/clear` 清空日志。
- `POST /api/models` 不可用。
- `PUT /api/models/:id` 不可用。
- `DELETE /api/models/:id` 不可用。
- 未知路径或方法返回统一错误。
- JSON 编码失败或内部异常返回统一错误，不泄露敏感配置。

### 完成条件

- 项目可构建。
- 阶段 3 范围内的本地 HTTP API 已实现。
- 阶段 3 验证方式中的测试通过。
- 阶段 1-2 回归测试仍通过。
- 测试覆盖阶段 3 列出的关键行为。
- API 不开放配置写入接口。
- API 响应不泄露 `command`、`workDir`、`env`。
- 完成证据写入本文档。
- `docs/PLAN_MAP.md` 状态和证据同步。

### 完成证据

待阶段 3 完成后补充。

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
