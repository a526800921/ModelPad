# 计划：ModelPad 启动接口环境变量覆盖

## 目标

在本地 HTTP API 的启动服务接口中加入环境变量配置能力，使外部调用方可以在启动某个模型时传入本次启动所需的额外环境变量。

默认解释：新增能力只作用于本次启动，不写回 `config.json`，不改变模型的持久化配置，也不在查询接口中返回环境变量。

## 背景

ModelPad v1 已完成本地 HTTP API，当前 `POST /api/models/:id/start` 只按已保存的模型配置启动服务。用户于 2026-07-04 增加需求：在启动服务接口里面加入环境变量配置。

现有边界：

- `ModelConfig.env` 和 `PythonScriptConfig.env` 已支持模型配置内的环境变量。
- `ModelProcessManager.start(config:)` 当前只接收完整 `ModelConfig`。
- `APIServer` 当前不会解析 `POST /api/models/:id/start` 的请求体。
- v1 契约要求 HTTP API 不开放新增、更新、删除模型配置，且查询响应不返回 `command`、`workDir`、`env`。

## 范围

- 为 `POST /api/models/:id/start` 增加可选 JSON 请求体。
- 请求体允许携带本次启动的环境变量覆盖。
- 启动时合并持久化配置中的环境变量和请求体中的环境变量。
- 请求体环境变量只对本次启动生效，不持久化。
- 查询模型、列出模型、日志和响应摘要仍不返回环境变量。
- 增加 API 契约测试，覆盖无请求体兼容、合法环境变量合并、非法请求体错误和不持久化。

## 非范围

- 不开放 `POST /api/models`、`PUT /api/models/:id` 或 `DELETE /api/models/:id`。
- 不允许外部 API 修改持久化模型配置。
- 不通过 API 返回 `command`、`workDir`、`env`。
- 不新增远程访问、鉴权或局域网监听。
- 不改变 UI 配置弹窗的环境变量编辑能力。
- 不把环境变量覆盖扩展到 `stop`、`logs` 或 `logs/clear` 接口。

## 公共 API 契约

### 启动请求

接口：

```http
POST /api/models/:id/start
Content-Type: application/json
```

请求体可省略。省略请求体时保持当前行为。

新增请求体：

```json
{
  "env": {
    "KEY": "value"
  }
}
```

字段语义：

| 字段 | 类型 | 必填 | 语义 |
|---|---|---:|---|
| `env` | object<string,string> | 否 | 本次启动追加或覆盖的环境变量 |

合并规则：

1. 先使用 ModelPad 进程自身环境。
2. 再合并模型持久化配置的有效环境变量。
3. 最后合并启动请求体中的 `env`。
4. 同名变量以请求体中的值为准。
5. 请求体中的 `env` 不写回 `config.json`。

兼容规则：

- 空请求体、空 JSON 对象 `{}`、`{"env":{}}` 均保持当前启动行为。
- 已经 `running` 或 `starting` 的模型仍按现有重复启动语义处理，不因为传入新 `env` 而重启或更新运行中进程环境。

错误处理：

| 场景 | 建议错误码 | HTTP 状态 | 说明 |
|---|---|---:|---|
| 请求体不是合法 JSON | `invalid_request` | 400 | 不启动模型 |
| `env` 不是对象 | `invalid_request` | 400 | 不启动模型 |
| `env` 的 key 或 value 不是字符串 | `invalid_request` | 400 | 不启动模型 |
| 环境变量 key 为空 | `invalid_request` | 400 | 不启动模型 |
| 模型不存在 | `model_not_found` | 404 | 沿用现有行为 |
| 启动失败 | `start_failed` | 400 | 沿用现有行为 |

## Step 0 证据

- `Sources/ModelPadCore/API/APIDTOs.swift` 当前没有启动请求 DTO。
- `Sources/ModelPadCore/API/APIServer.swift` 当前 `handleStart(id:)` 不读取 `bodyBuffer`。
- `Sources/ModelPadCore/Process/ModelProcessManager.swift` 当前 `start(config:)` 使用 `config.effectiveEnv()` 注入环境变量。
- `Tests/ModelPadCoreTests/APITests/APIContractTests.swift` 当前覆盖 API 契约，但尚未覆盖启动请求体中的环境变量。
- 既有契约要求 API 查询不泄露 `env`，新需求不能破坏该边界。

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | 启动接口一次性环境变量覆盖 | 需求确认本计划契约 | API 契约测试和进程环境注入测试通过；配置文件未被请求体 env 改写 | 已完成 |

## 实施方向

1. 新增 `StartModelRequest` DTO，包含可选 `env: [String: String]?`。
2. 让 `APIServer` 在 `POST /api/models/:id/start` 中解析可选请求体。
3. 对请求体做结构校验，非法请求体返回 `invalid_request`，且不启动模型。
4. 为本次启动创建运行时配置副本，合并请求体 `env` 后传给 `ModelProcessManager.start`。
5. 保持 `ConfigStore` 不保存请求体 `env`。
6. 如 `restart` 暂不支持请求体环境变量，应在测试中固定该边界，避免隐式扩散。

## 验证方式

阶段 1 完成时至少验证：

- 不带请求体调用 `POST /api/models/:id/start` 仍可启动模型。
- 请求体 `{"env":{"TEST_VAR":"value"}}` 能注入到被启动进程。
- 请求体 `env` 可覆盖模型配置中的同名环境变量。
- 启动后重新读取 `config.json`，请求体 `env` 未被持久化。
- 非法 JSON、非对象 `env`、非字符串 key/value、空 key 均返回 `invalid_request`，并且不启动模型。
- `GET /api/models` 和 `GET /api/models/:id` 仍不返回 `env`。
- `swift test` 通过。

## 完成条件

- 启动接口环境变量覆盖契约实现完成。
- 相关 API 和进程环境注入测试通过。
- 不持久化、不泄露环境变量的边界通过测试固定。
- 完成证据写入本文档，并同步 `docs/PLAN_MAP.md`。

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 外部调用方误以为请求体 `env` 会保存 | 下次启动缺少变量 | 文档和测试明确“一次性覆盖” | 删除请求体 `env` 使用，改回 UI 持久化配置 |
| 请求体 env 覆盖关键系统变量 | 启动失败或行为漂移 | 保持仅本机 API；失败写入启动错误和日志 | 不传覆盖变量，恢复持久化配置启动 |
| POST body 无大小限制被放大 | 本机误调用导致内存峰值 | 后续可单独增加 API body 大小上限 | 临时限制调用方请求体大小 |

## 阶段 1 完成证据

阶段 1 已于 2026-07-04 完成。

实施范围：

- `Sources/ModelPadCore/API/APIDTOs.swift`：新增 `StartModelRequest` DTO（含可选 `env: [String: String]?` 和 `validate()`）。
- `Sources/ModelPadCore/Process/ModelProcessManager.swift`：`start()` 新增 `envOverrides` 参数，合并优先级为 进程环境 → config 持久化 env → 请求体 env。
- `Sources/ModelPadCore/API/APIServer.swift`：`handleStart` 解析可选 JSON 请求体，非法请求体返回 `invalid_request`（400）且不启动模型。
- `Tests/ModelPadCoreTests/APITests/APIContractTests.swift`：新增 11 个契约测试。

测试结果（2026-07-04）：

```text
swift test → 120 tests passed (7 suites)
```

新增测试覆盖：

| 测试 | 结果 |
|---|---|
| 无请求体启动（向后兼容） | ✅ |
| 空 JSON 对象启动 | ✅ |
| 空 env 对象启动 | ✅ |
| env 覆盖持久化 config 同名变量 | ✅ |
| 请求体 env 不持久化到 config.json | ✅ |
| 非法 JSON → 400 invalid_request 且不启动 | ✅ |
| env 非对象 → 400 | ✅ |
| env 含空 key → 400 | ✅ |
| env 值非字符串 → 400 | ✅ |
| 模型列表和单模型摘要不泄露 env | ✅ |
| 原有所有 API 契约测试回归 | ✅ |

Git commit: `83eeb9c`

## 测试覆盖率

验收复核（2026-07-04）：

```text
swift test → 120 tests passed (7 suites)
```

覆盖范围：

- API 契约测试覆盖启动接口无请求体、空 JSON、空 env、env 覆盖、不持久化、非法请求体和查询不泄露 env。
- 进程层既有测试覆盖模型配置 env 注入；本阶段新增 API 测试覆盖请求体 env 覆盖持久化 env 的优先级。
- 回归测试覆盖配置编解码、配置存储、进程生命周期、日志缓冲、TCP 健康检查和 App ViewModel 装配。

## 未决问题

| 问题 | 推荐方案 | 是否阻塞当前阶段 | 状态 |
|---|---|---|---|
| `restart` 是否也接受一次性 env | 第一阶段不支持，避免重启语义扩大；后续如需要再单独加契约 | 否 | 待确认 |
| 是否需要环境变量 key 白名单或黑名单 | 暂不加，保持本地 API 简洁；非法结构校验即可 | 否 | 待确认 |
