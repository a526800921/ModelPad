# ModelPad — v1 设计

> macOS 原生模型管理面板，用于管理本机多种推理引擎的启动配置、进程生命周期、实时日志，并暴露本机 HTTP API 供本机工具查询和启停模型。

## 概述

- **定位**: 个人使用的 macOS 原生应用
- **技术栈**: Swift / SwiftUI (macOS 14+)
- **管理的模型类型**: Ollama、llama.cpp、vLLM、自定义脚本等本地推理引擎
- **核心功能**: 保存启动命令、启动/停止模型、查看实时日志、本地 HTTP API
- **API 范围**: 只开放查询、日志和生命周期控制，不开放新增/更新/删除配置

---

## 整体架构

```
┌─────────────────────────────────────────┐
│              ModelPad.app               │
│                                         │
│  ┌──────────┐  ┌──────────────────────┐ │
│  │ SwiftUI  │  │   Local API Server   │ │
│  │ 前端界面  │  │   (HTTP, 127.0.0.1)  │ │
│  └────┬─────┘  └──────────┬───────────┘ │
│       │                   │             │
│  ┌────┴───────────────────┴──────────┐  │
│  │          ModelManager             │  │
│  │    启动 / 停止 / 监控模型进程       │  │
│  └────┬──────────────────────────────┘  │
│       │                                 │
│  ┌────┴────┐  ┌──────────┐              │
│  │ Process │  │  Config  │              │
│  │ Monitor │  │  Store   │              │
│  │ 健康检查 │  │  JSON    │              │
│  └─────────┘  └──────────┘              │
└─────────────────────────────────────────┘
```

### 模块职责

| 模块 | 职责 | 对外接口 |
|------|------|---------|
| SwiftUI 界面 | 单窗口管理面板，模型配置编辑、启停、日志查看 | App 内部 |
| Menu Bar Item | 常驻菜单栏图标，左键点击打开面板 | App 内部 |
| Local API Server | 嵌入式 HTTP 服务，只监听 `127.0.0.1` | REST API |
| ModelManager | 模型生命周期管理，进程 spawn / stop / restart | Swift API + REST |
| Process Monitor | 进程状态监控、TCP 端口健康检查 | 内部通知 |
| Log Buffer | 捕获 stdout / stderr / system 日志 | Swift API + REST |
| Config Store | 模型配置和 API 设置持久化 | Swift API |

---

## 数据模型

```swift
enum Engine: String, Codable, CaseIterable {
    case ollama
    case llamacpp
    case vllm
    case custom
}

enum ModelStatus: String, Codable {
    case stopped
    case starting
    case running
    case error
}

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

struct RuntimeModelState {
    var status: ModelStatus
    var pid: Int32?
}
```

核心配置实体只有 `ModelConfig`。`command` 保存完整启动命令字符串，不拆分 executable 和 arguments，保持对不同推理引擎和自定义脚本的兼容。

`status`、`pid`、日志、进程句柄都是运行态数据，只存在内存中，不作为可信配置持久化。应用启动后，所有模型初始视为 `stopped`。

### Engine 用途

`Engine` 只用于分类、图标、筛选和启动命令模板，不决定启动逻辑。所有模型统一通过 `command` 启动。

新增模型时可以按引擎预填模板：

```bash
# Ollama
ollama serve

# llama.cpp
./llama-server -m /path/to/model.gguf --port 8080

# vLLM
python -m vllm.entrypoints.openai.api_server --model /path/to/model --port 8000

# custom
/path/to/script.sh
```

---

## 进程生命周期

### 启动

1. 用户点击启动，或调用 `POST /api/models/:id/start`。
2. 如果模型已经 `running`，直接返回当前状态和 pid。
3. 如果模型正在 `starting`，返回正在启动状态，不重复启动。
4. 如果模型是 `stopped` 或 `error`，允许启动。
5. 启动前自动保存 UI 中未保存的配置；保存失败则阻止启动。
6. 清空该模型上一轮内存日志，并写入本次启动的 system 日志。
7. 使用 Foundation `Process` 启动命令。
8. 状态改为 `starting`。
9. 如果配置了 `port`，等待 TCP 端口连通；连通后改为 `running`。
10. 如果没有配置 `port`，进程成功 spawn 后直接改为 `running`。

完整命令统一通过 shell 执行：

```swift
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = ["-lc", command]
```

这允许命令包含 shell 语法，例如环境变量、管道、`source .venv/bin/activate`、`cd` 等。

### 停止

1. 用户点击停止，或调用 `POST /api/models/:id/stop`。
2. 如果没有运行进程，状态置为 `stopped`。
3. 如果有运行进程，先优雅终止。
4. 等待短超时，例如 5 秒。
5. 仍未退出时强制结束。
6. 状态置为 `stopped`。
7. 保留本轮内存日志，直到下次启动或用户清空。

### 重启

`restart` 等价于先停止再启动。失败原因写入该模型日志。

### App 生命周期

- 点击窗口关闭按钮：隐藏主窗口，不退出应用，不停止模型。
- 点击菜单栏图标：打开 / 显示主窗口。
- 完全退出 App 时：停止所有由 ModelPad 启动的模型进程，并停止本地 API Server。
- 同一个模型同一时间只允许一个托管进程实例。

---

## 健康检查

v1 只做 TCP 端口连通检查，不做引擎专用 HTTP 路径检查。

- 有 `port`：启动后最多等待 30 秒端口可连接。
- 无 `port`：进程成功 spawn 后直接视为 `running`。
- `starting` 阶段进程退出：状态改为 `error`。
- `running` 阶段进程异常退出：状态改为 `error`。
- 用户手动停止：状态改为 `stopped`，不算错误。

后续可扩展 `healthURL`，支持 `/health`、`/v1/models`、Ollama `/api/tags` 等专用检查。

---

## 日志

v1 使用内存环形缓冲，不写盘。

- 每个模型维护独立日志缓冲。
- 捕获 stdout、stderr。
- ModelPad 自己产生的事件写入 system 日志。
- 每条日志包含时间、来源和内容。
- 每个模型保留最近 2000 行。
- 单行最多保留 8000 字符，超长截断。
- 每次启动默认清空旧日志。
- 停止后日志保留，直到下次启动或用户清空。

日志记录结构：

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

UI 日志区提供：

- 实时日志输出
- 自动滚动到底部
- 清空日志
- 复制日志
- stdout / stderr / system 的视觉区分

---

## 本地 HTTP API

默认监听：

```text
127.0.0.1:9999
```

v1 不做鉴权，不支持远程访问，不监听局域网地址。HTTP API 只用于本机工具查询模型状态、读取日志、启停模型。

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

以下配置写入能力不对 HTTP API 开放，只能通过 ModelPad UI 操作：

| 方法 | 路径 | 原因 |
|------|------|------|
| `POST` | `/api/models` | 外部 API 不允许新增可执行命令 |
| `PUT` | `/api/models/:id` | 外部 API 不允许修改启动命令 |
| `DELETE` | `/api/models/:id` | 外部 API 不允许删除配置 |

### 模型摘要

HTTP API 不返回 `command`、`workDir`、`env`，避免暴露本地路径、环境变量或命令参数。

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

### 示例

```http
GET /api/models
```

```json
{
  "ok": true,
  "models": [
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
  ]
}
```

```http
POST /api/models/:id/start
```

```json
{
  "ok": true,
  "pid": 12345,
  "status": "running"
}
```

```http
GET /api/models/:id/logs
```

```json
{
  "ok": true,
  "logs": [
    {
      "time": "2026-06-30T12:00:00Z",
      "stream": "stdout",
      "message": "server listening on 11434"
    }
  ]
}
```

---

## UI 布局

```
┌────────────┬──────────────────────────┐
│  模型列表   │                          │
│            │     模型详情 / 配置        │
│  ● Qwen-7B │                          │
│  ○ Llama-3 │   命令: ollama run ...    │
│  ● DeepSeek│   端口: 11434             │
│  ✕ Mistral │   状态: 运行中             │
│            │                          │
│  [+ 添加]  │   [启动] [停止] [重启]     │
│  [- 删除]  │   [保存]                  │
│            │                          │
│            │   ┌──────────────────┐   │
│            │   │   实时日志输出    │   │
│            │   │   ...            │   │
│            │   └──────────────────┘   │
└────────────┴──────────────────────────┘
```

### 左侧边栏

- 模型列表。
- 状态指示：
  - 绿色：`running`
  - 黄色：`starting`
  - 灰色：`stopped`
  - 红色：`error`
- 每项显示模型名称、引擎标签、端口或“未配置端口”。
- 底部提供添加和删除按钮。

### 右侧主区域

右侧主区域包含三块：

1. 基本配置
   - 名称
   - 引擎
   - 启动命令
   - 工作目录
   - 环境变量
   - 端口

2. 操作区
   - 启动
   - 停止
   - 重启
   - 保存
   - 当前状态
   - pid

3. 日志区
   - 实时日志
   - 清空日志
   - 复制日志

### 交互规则

- 选中左侧模型后，右侧显示详情。
- 配置有改动时显示未保存状态。
- 切换模型前，如果有未保存改动，提示保存或放弃。
- 启动前自动保存未保存配置。
- 删除运行中模型时，提示会先停止再删除。
- 启动中禁用启动按钮。
- 未运行时禁用停止按钮。
- 日志不参与配置保存。

### 工具栏

主窗口工具栏提供：

- 全部启动
- 全部停止

全部启动规则：

- 按左侧模型列表顺序依次启动。
- 只启动 `stopped` 或 `error` 模型。
- 跳过 `running` 和 `starting` 模型。
- 某个模型启动失败，不中断后续模型。
- 失败原因查看该模型日志。

全部停止规则：

- 按左侧模型列表顺序依次停止。
- 只停止 `running` 或 `starting` 模型。
- 跳过 `stopped` 模型。
- 停止失败则状态置为 `error` 并写入日志。

---

## 菜单栏行为

ModelPad 启动后在 macOS 右上角创建一个菜单栏图标。

- 左键点击菜单栏图标：打开 / 显示 ModelPad 面板。
- 不弹出菜单。
- 不在菜单栏里显示模型列表。
- 不在菜单栏里提供启动、停止、重启、全部启动、全部停止。
- 完全退出 App 时停止所有由 ModelPad 启动的模型进程。

实现上可使用 `NSStatusItem`，设置 button action 为显示主窗口，不设置 menu。

---

## 配置持久化

v1 使用 JSON 文件持久化，不使用 SwiftData。

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
    "port": 9999
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

规则：

- App 启动时读取配置。
- 文件不存在时创建默认空配置。
- 保存配置时原子写入：先写临时文件，再 rename 覆盖。
- JSON 读失败时保留损坏文件备份，例如 `config.json.bak`，然后启动空配置并在 UI 显示错误。
- `createdAt` 创建后不变。
- `updatedAt` 每次保存模型配置时更新。
- `status`、`pid`、日志、进程句柄不写入配置文件。

---

## 技术选型

| 层 | 选型 | 说明 |
|----|------|------|
| UI | SwiftUI | macOS 14+ 原生 |
| 菜单栏图标 | AppKit `NSStatusItem` | 左键点击打开面板 |
| 本地 HTTP | SwiftNIO 或 Vapor | 嵌入式，监听 `127.0.0.1` |
| 持久化 | JSON 文件 | `~/Library/Application Support/ModelPad/config.json` |
| 进程管理 | Foundation `Process` | 统一通过 `/bin/zsh -lc` 执行命令 |
| 健康检查 | TCP connect | v1 不做引擎专用 HTTP 检查 |
| 日志 | Pipe + 内存环形缓冲 | stdout / stderr / system |

---

## v1 不包含

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

---

## v1 核心边界

ModelPad v1 是一个本机模型进程管理面板：

- 配置只能通过 UI 创建、修改、删除。
- 外部工具只能通过 HTTP API 查询状态、读取日志、启动、停止、重启模型。
- 进程由 ModelPad 托管。
- 窗口关闭不代表退出。
- App 完全退出时，停止所有由 ModelPad 启动的模型。
