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
| 阶段 2 | 进程托管、状态机、健康检查和日志缓冲 | 阶段 1 完成 | 使用短生命周期 fixture 进程验证启动、停止、异常退出、TCP 健康检查、日志截断 | 候选 |
| 阶段 3 | 本地 HTTP API | 阶段 2 完成 | API 契约测试覆盖允许接口、禁止配置写入接口、敏感字段不泄露 | 候选 |
| 阶段 4 | SwiftUI 主面板和菜单栏打开面板 | 阶段 3 完成 | 手动验收 UI 工作流；必要时补充 ViewModel 单元测试 | 候选 |
| 阶段 5 | 集成验收和打包前收口 | 阶段 4 完成 | 端到端验收清单通过，文档和 `PLAN_MAP.md` 同步 | 候选 |

## 当前阶段

当前阶段：阶段 1 已完成，下一步阶段 2（进程托管、状态机、健康检查和日志缓冲）。

阶段 1 项目结构决策：优先建立 Swift Package 承载核心模型、配置持久化和单元测试；SwiftUI App/Xcode 目标在阶段 4 补齐。这样阶段 1 可以先获得可运行测试和清晰的核心模块边界。

### 范围

- 建立 macOS Swift / SwiftUI 项目骨架。
- 定义 `Engine`、`ModelStatus`、`ModelConfig`、配置根对象等基础模型。
- 实现 JSON 配置读写。
- 配置路径使用 `~/Library/Application Support/ModelPad/config.json`。
- 实现默认空配置。
- 实现配置保存的原子写入。
- 实现 JSON 损坏文件备份和空配置降级。
- 添加阶段 1 所需测试。

### 非范围

- 不实现真实进程启动。
- 不实现 HTTP API。
- 不实现完整 SwiftUI 主界面。
- 不实现菜单栏图标。

### 实施步骤

1. 确认项目结构和构建方式。
2. 创建或调整 Swift 项目骨架。
3. 实现配置模型。
4. 实现配置路径解析和 JSON Store。
5. 实现原子写入和损坏文件备份。
6. 添加单元测试。
7. 运行验证并记录证据。
8. 同步 `docs/PLAN_MAP.md` 状态和完成证据。

### Step 0 证据

当前仓库基线：

- 截至 2026-06-30，仓库根目录只有 `DESIGN.md` 和本次初始化的治理文档。
- 尚无 Swift 项目骨架、源码目录、测试目标或构建配置。
- `DESIGN.md` 已作为背景材料存在，但不再作为 v1 规范事实源。
- `docs/PLAN_MAP.md` 已建立计划索引。
- 本文档已承载 v1 的目标、非目标、数据模型、配置契约、API 契约、阶段和阶段 1 完成条件。

阶段 1 的可观察基线：

- 配置文件目标路径固定为 `~/Library/Application Support/ModelPad/config.json`。
- 初始配置应为空模型列表，API 默认启用，host 为 `127.0.0.1`，port 为 `9786`。
- 损坏 JSON 必须备份并降级为空配置，而不是导致 App 无法启动。

### 验证方式

阶段 1 完成时至少运行：

- 项目构建命令。
- Swift 单元测试。
- 配置读写测试。
- 损坏 JSON 备份测试。

如果项目脚本尚未建立，阶段 1 需要在完成记录中写明实际使用的 `swift test`、`xcodebuild test` 或等效命令。

### 测试覆盖率

阶段 1 不强制覆盖率百分比门槛，但必须覆盖：

- `Engine` / `ModelStatus` 编解码。
- `ModelConfig` 编解码。
- 默认配置创建。
- 配置保存后重新读取。
- 原子写入行为。
- 损坏 JSON 备份和空配置降级。

### 完成条件

- 项目可构建。
- 阶段 1 范围内的配置模型和 JSON Store 已实现。
- 阶段 1 验证方式中的测试通过。
- 测试覆盖阶段 1 列出的关键行为。
- 完成证据写入本文档。
- `docs/PLAN_MAP.md` 状态和证据同步。

### 完成证据

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
