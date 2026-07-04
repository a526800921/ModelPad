# ModelPad

ModelPad 是一个 macOS 菜单栏应用，用来统一托管本机模型服务进程。它负责从配置启动模型、做基础健康检查、查看日志、停止进程，并提供只监听本机的 HTTP API 给外部 workflow 调用。

## 功能概览

- 菜单栏常驻，不显示在程序坞。
- 点击菜单栏图标打开菜单，展示全部已配置服务及运行状态点，可显示主面板或退出。
- 完全退出 App 时会停止由 ModelPad 启动的全部模型进程。
- 支持命令行启动和 Python 脚本启动两种模型配置。
- 支持按模型查看操作区和日志区，配置编辑在弹窗中完成。
- 本地 API 只提供读取、启停和日志能力，不开放新增、更新、删除模型配置。

## 运行

开发运行：

```bash
swift run ModelPad
```

构建 `.app`：

```bash
./scripts/build_app.sh
```

构建后启动：

```bash
open dist/ModelPad.app
```

构建并自动启动：

```bash
./scripts/build_app.sh --run
```

跳过测试构建：

```bash
./scripts/build_app.sh --skip-tests
```

## 配置文件

默认配置文件：

```text
~/Library/Application Support/ModelPad/config.json
```

配置结构示例：

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
      "id": "40621169-461C-4018-974E-9FAC92A542E7",
      "name": "pdf",
      "engine": "custom",
      "command": "",
      "workDir": null,
      "env": {
        "PYENV_ROOT": "/Users/jafish/.pyenv"
      },
      "port": 9000,
      "launchMode": "pythonScript",
      "pythonScript": {
        "scriptPath": "/path/to/server.py",
        "arguments": ["--host", "127.0.0.1", "--port", "9000"],
        "pythonExecutable": "/path/to/python",
        "workDir": null,
        "env": {}
      },
      "createdAt": "2026-07-04T00:00:00Z",
      "updatedAt": "2026-07-04T00:00:00Z"
    }
  ]
}
```

字段说明：

| 字段 | 说明 |
|---|---|
| `api.enabled` | 是否启用本地 HTTP API |
| `api.host` | API 监听地址，默认 `127.0.0.1` |
| `api.port` | API 监听端口，默认 `9786` |
| `engine` | 模型分类标签，可选 `ollama`、`llamacpp`、`vllm`、`custom`、`mlx` |
| `launchMode` | 启动模式，`command` 或 `pythonScript` |
| `command` | `launchMode=command` 时使用的完整启动命令 |
| `workDir` | 命令工作目录 |
| `env` | 模型级环境变量 |
| `port` | 模型服务端口；配置后启动时会做 TCP 健康检查 |
| `pythonScript` | Python 脚本启动配置，仅 `launchMode=pythonScript` 时生效 |

## 本地 HTTP API

默认监听：

```text
http://127.0.0.1:9786
```

如果本机 shell 设置了代理，调用本地 API 时建议绕过代理：

```bash
curl --noproxy '*' http://127.0.0.1:9786/api/health
```

### 开放接口

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/api/health` | API 健康检查 |
| `GET` | `/api/models` | 获取全部模型运行摘要 |
| `GET` | `/api/models/:id` | 获取单个模型运行摘要 |
| `POST` | `/api/models/:id/start` | 启动模型 |
| `POST` | `/api/models/:id/stop` | 停止模型 |
| `POST` | `/api/models/:id/restart` | 重启模型 |
| `GET` | `/api/models/:id/logs` | 获取模型日志 |
| `POST` | `/api/models/:id/logs/clear` | 清空模型日志 |

### 不开放接口

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST` | `/api/models` | 不允许外部新增模型配置 |
| `PUT` | `/api/models/:id` | 不允许外部更新模型配置 |
| `DELETE` | `/api/models/:id` | 不允许外部删除模型配置 |

外部 API 不暴露模型的 `command`、`workDir`、`env` 等敏感启动细节。

### 响应示例

健康检查：

```bash
curl --noproxy '*' http://127.0.0.1:9786/api/health
```

```json
{
  "ok": true
}
```

模型列表：

```bash
curl --noproxy '*' http://127.0.0.1:9786/api/models
```

```json
{
  "ok": true,
  "models": [
    {
      "id": "40621169-461C-4018-974E-9FAC92A542E7",
      "name": "pdf",
      "engine": "custom",
      "port": 9000,
      "status": "running",
      "pid": 92833,
      "baseUrl": "http://127.0.0.1:9000",
      "createdAt": "2026-07-04T00:00:00Z",
      "updatedAt": "2026-07-04T00:00:00Z"
    }
  ]
}
```

启动模型：

```bash
curl --noproxy '*' -X POST http://127.0.0.1:9786/api/models/<model-id>/start
```

响应：

```json
{
  "ok": true,
  "status": "running",
  "pid": 92833
}
```

启动时支持可选 JSON 请求体，传入一次性环境变量覆盖（不持久化到 config.json）：

```bash
curl --noproxy '*' -X POST http://127.0.0.1:9786/api/models/<model-id>/start \
  -H "Content-Type: application/json" \
  -d '{"env": {"MINERU_API_OUTPUT_ROOT": "/tmp/custom-output"}}'
```

合并规则：进程环境 → config.json 持久化 env → 请求体 env（最终胜出）。请求体 env 仅对本次启动生效；已经 running/starting 的模型重复调用 start 不会因传入新 env 而重启。

停止模型：

```bash
curl --noproxy '*' -X POST http://127.0.0.1:9786/api/models/<model-id>/stop
```

```json
{
  "ok": true,
  "status": "stopped"
}
```

获取日志：

```bash
curl --noproxy '*' http://127.0.0.1:9786/api/models/<model-id>/logs
```

```json
{
  "ok": true,
  "logs": [
    {
      "time": "2026-07-04T00:00:00Z",
      "stream": "system",
      "message": "model stopped"
    }
  ]
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

常见错误码：

| code | 说明 |
|---|---|
| `invalid_request` | 请求体格式非法 |
| `not_found` | 路由不存在 |
| `model_not_found` | 模型不存在 |
| `start_failed` | 启动失败 |
| `restart_failed` | 重启失败 |

## 外部 workflow 接入约定

外部调用方应只通过 ModelPad 托管的模型服务端口或 ModelPad 本地 API 调用模型，不应直接杀端口进程。

以 PDF workflow 为例：

- ModelPad 托管 `pdf` 模型并监听 `127.0.0.1:9000`。
- `/Users/jafish/Documents/work/mineru-pdf-workflow` 只复用已有服务。
- workflow 不负责启动、重启、停止或清理 ModelPad 托管的服务进程。
- 如果未检测到服务，workflow 应提示先启动 ModelPad PDF 服务并退出。

## 开发验证

运行全部测试：

```bash
swift test
```

运行计划治理检查：

```bash
python3 /Users/jafish/.codex/skills/plan-governance/scripts/check_plan_governance.py .
```

构建 App：

```bash
./scripts/build_app.sh
```

## 计划文档

治理入口：

```text
docs/PLAN_MAP.md
```

主要计划：

- `docs/plans/modelpad-v1.md`
- `docs/plans/modelpad-menu-bar-agent.md`
- `docs/plans/modelpad-logbuffer-performance.md`
- `docs/plans/modelpad-workflow-compat.md`
- `docs/plans/modelpad-pdf-model-optimization.md`
- `docs/plans/modelpad-api-start-env-overrides.md`
- `docs/plans/modelpad-menu-service-list.md`
