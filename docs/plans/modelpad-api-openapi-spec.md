# ModelPad API OpenAPI 规范

## 目标

为 ModelPad 本地 HTTP API 提供自描述的 OpenAPI 3.1.0 规范端点 `GET /openapi.json`，方便外部 workflow 自动发现接口。

## 范围

- 在 APIServer 的 `route` 方法中注册 `GET /openapi.json` 路由。
- 生成完整的 OpenAPI 3.1.0 规范 JSON，覆盖所有现有 API 端点及其请求/响应 Schema。
- 响应 `Content-Type: application/json`。

## 非范围

- 不修改现有 API 的行为、响应格式或状态码。
- 不引入 API 版本控制。

## 方案

### 路由

`APIServer.swift` 的 `APIHandler.route(method:path:)` 中，在 `/api/health` 之后注册：

```swift
if method == .GET, path == "/openapi.json" {
    return .json(Self.openapiSpec)
}
```

### APIResponse 扩展

`APIDTOs.swift` 的 `APIResponse` 枚举新增 `.json(Data)` case，用于返回裸 JSON（`Content-Type: application/json`）。

### OpenAPI 规范生成

`APIHandler` 内新增 `openapiSpec` 静态属性，使用 `JSONSerialization` 构建并缓存完整 OpenAPI 3.1.0 规范，包含：

- 全部 9 个已有端点的路径定义（method、参数、请求体、响应格式）
- `ModelSummary`、`LogEntry`、`ErrorResponse` 三个 JSON Schema
- 统一的 `404` 错误响应模板

使用 `SpecField` 递归枚举 + 辅助方法 `specOperation` / `specResponseSchema` 保持规范生成代码的可读性。

### 风险与回滚

- **风险**：无。新端点不修改既有行为，不影响任何模型启停或配置逻辑。
- **回滚**：删除 `openapiSpec` 属性和对应的路由分支，恢复 `APIResponse` 枚举。

### 未决问题

无。

## 状态

- 当前阶段：已完成
- 状态：`已完成`

## 验证方式

```bash
curl -s http://127.0.0.1:9999/openapi.json | jq '.info.title'
# → "ModelPad API"
```

## 完成条件

- [x] `GET /openapi.json` 返回有效 OpenAPI 3.1.0 JSON
- [x] 规范覆盖所有 9 个已有端点
- [x] Swift 构建通过

## Step 0 证据

执行前 API 无 OpenAPI 端点：

```bash
curl -s http://127.0.0.1:9999/openapi.json
# → {"ok":false,"error":{"code":"not_found","message":"Route not found"}}
```

## 完成证据

构建通过（1.41s），端点可访问：

```bash
# 构建通过
swift build  # → Build complete! (1.41s)

# 端点响应
curl -s http://127.0.0.1:9999/openapi.json | jq '.info | {title, version}'
# → {"title": "ModelPad API", "version": "1.0.0"}

# 覆盖全部 9 个端点
curl -s http://127.0.0.1:9999/openapi.json | jq '.paths | keys'
# → [
#     "/api/config/reload",     "/api/health",
#     "/api/models",            "/api/models/{id}",
#     "/api/models/{id}/logs",  "/api/models/{id}/logs/clear",
#     "/api/models/{id}/restart","/api/models/{id}/start",
#     "/api/models/{id}/stop"
#   ]
```
