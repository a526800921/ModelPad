# 计划：ModelPad PDF 模型优化方案

## 目标

优化 ModelPad 托管的 `pdf` 模型启动配置和运行环境，使 MinerU FastAPI 服务在本地常驻场景下更稳定、可观测、可清理，并减少外部 workflow 与服务端环境变量不一致导致的性能漂移。

首轮优化对象是当前 `pdf` 模型：

- 服务脚本：`App/Resources/Scripts/mineru_fast_api.py`
- 监听地址：`127.0.0.1:9000`
- 运行方式：ModelPad `pythonScript`
- 调用方：`/Users/jafish/Documents/work/mineru-pdf-workflow`

## 范围

- 明确 `pdf` 模型推荐环境变量和启动参数。
- 明确哪些优化应放在 ModelPad 模型配置，哪些应继续由外部 workflow 请求参数控制。
- 明确冷启动、内存、日志、输出目录、任务保留时间的取舍。
- 给出可分阶段实施和回滚的配置方案。
- 给出验证方式，确保优化不破坏 `mineru-pdf-workflow` 的现有调用路径。

## 非范围

- 不修改 MinerU 业务解析算法。
- 不改变 `mineru-pdf-workflow` 输出包结构。
- 不新增远程监听、鉴权或公网访问。
- 不在本计划中直接改代码；实施需用户确认后单独执行。
- 不把 `MINERU_API_MAX_CONCURRENT_REQUESTS` 作为 macOS 优化项，因为当前脚本在 macOS 上强制单并发。

## 当前阶段

当前阶段：阶段 1 实施中（配置已更新，待最小 PDF workflow 验收）。

本阶段已执行配置层更新；完成闭环前还需使用 `/Users/jafish/Documents/work/mineru-pdf-workflow` 最小样本跑通一次解析。

## Step 0 证据

- ModelPad 当前 `pdf` 配置位于 `~/Library/Application Support/ModelPad/config.json`。
- `pdf` 模型当前字段：
  - `name`: `pdf`
  - `port`: `9000`
  - `launchMode`: `pythonScript`
  - `pythonScript.scriptPath`: `/Users/jafish/Documents/work/ModelPad/App/Resources/Scripts/mineru_fast_api.py`
  - `pythonScript.arguments`: `--host 127.0.0.1 --port 9000 --enable-vlm-preload False`
  - `env`: 仅包含 `PYENV_ROOT=/Users/jafish/.pyenv`
- 当前 `9000` 端口未监听，说明检查时 `pdf` 服务未运行。
- `mineru_fast_api.py` 暴露的启动参数包括 `--host`、`--port`、`--reload`、`--allow-public-http-client`、`--enable-vlm-preload`。
- `mineru_fast_api.py` 在 macOS 上强制 `max_concurrent_requests = 1`；因此通过 `MINERU_API_MAX_CONCURRENT_REQUESTS` 提高并发对当前本机服务端不生效。
- 本机 MinerU 版本为 `3.4.0`。
- 本机 `~/mineru.json` 配置：
  - `model-source`: `modelscope`
  - `models-dir.pipeline`: `/Users/jafish/.cache/modelscope/hub/models/OpenDataLab/PDF-Extract-Kit-1___0`
  - `models-dir.vlm`: `/Users/jafish/.cache/huggingface/hub/models--opendatalab--MinerU2.5-Pro-2605-1.2B/snapshots/bff20d4ae2bf202df9f45284b4d43681555a97ed`
- `mineru.utils.config_reader.get_device()` 当前返回 `mps`。
- `/Users/jafish/Documents/work/mineru-pdf-workflow` 的脚本默认设置过：
  - `MINERU_DEVICE_MODE=mps`
  - `MINERU_PDF_RENDER_THREADS=2`
  - `MINERU_PROCESSING_WINDOW_SIZE=8`
  - `MINERU_API_MAX_CONCURRENT_REQUESTS=1`
- 若 `pdf` 服务已由 ModelPad 常驻启动，外部 workflow 后续设置的环境变量不会影响已运行服务端，因此服务端相关环境变量应放入 ModelPad 模型配置。

## 推荐配置

### ModelPad `pdf.env`

建议把以下环境变量加入 `pdf` 模型配置：

| 变量 | 推荐值 | 目的 | 备注 |
|---|---|---|---|
| `PYENV_ROOT` | `/Users/jafish/.pyenv` | 保留当前 Python 环境 | 已存在 |
| `MINERU_DEVICE_MODE` | `mps` | 固定使用 Apple Silicon MPS | 避免运行环境漂移 |
| `MINERU_PDF_RENDER_THREADS` | `2` | 控制 PDF 渲染线程数 | 与 workflow 当前默认一致 |
| `MINERU_PROCESSING_WINDOW_SIZE` | `8` | 控制处理窗口大小 | 与 workflow 当前默认一致，降低内存峰值 |
| `MINERU_API_OUTPUT_ROOT` | `/Users/jafish/Documents/models/mineru-api-output` | 固定 API 任务输出目录 | 避免落到相对路径 `./output` |
| `MINERU_API_ENABLE_FASTAPI_DOCS` | `0` | 关闭本地常驻服务文档端点 | 减少无关端点和启动噪声 |
| `MINERU_API_DISABLE_ACCESS_LOG` | `1` | 关闭 uvicorn access log | 降低 ModelPad 日志噪声 |
| `MINERU_API_TASK_RETENTION_SECONDS` | `21600` | 任务结果保留 6 小时 | 若需要长时间回查可保持默认 86400 |

不建议作为首轮优化加入：

| 变量 | 原因 |
|---|---|
| `MINERU_API_MAX_CONCURRENT_REQUESTS` | 当前 macOS 分支强制单并发，设置后无实际收益 |
| `MINERU_FORMULA_ENABLE` / `MINERU_TABLE_ENABLE` | 属于解析质量和请求语义，应由 workflow 或单次请求控制 |
| `MINERU_API_PUBLIC_BIND_EXPOSED` | 当前仅本机 `127.0.0.1` 监听，不需要公网暴露语义 |

### `pythonScript.arguments`

保留当前基础参数：

```text
--host 127.0.0.1
--port 9000
--enable-vlm-preload False
```

`--enable-vlm-preload` 是否改为 `True` 取决于使用模式：

| 模式 | 推荐值 | 取舍 |
|---|---|---|
| 偶尔解析、希望低空闲内存 | `False` | 服务启动快、空闲更省资源，但首次解析慢 |
| 常驻服务、频繁解析、重视首次请求速度 | `True` | 启动更慢、空闲内存更高，但首次解析延迟更低 |

首轮推荐保持 `False`，先把环境变量和输出目录收敛；确认内存余量稳定后再单独评估 VLM 预加载。

## 分阶段方案

| 阶段 | 目标 | 变更 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | 配置层稳定性优化 | 更新 `pdf.env`，固定设备、线程、窗口、输出目录、日志和任务保留时间 | 启动服务、健康检查、跑最小 PDF workflow | 已完成 |
| 阶段 2 | 冷启动优化评估 | 评估 `--enable-vlm-preload True` | 对比启动时间、首次解析时间、空闲内存 | 候选 |
| 阶段 3 | workflow 契约收敛 | 确认外部 workflow 不再依赖启动后 env 注入服务端 | 跑 `pdf-seg` / `pdf-auto`，确认服务端配置生效且不会被误杀 | 候选 |

## 阶段 1 实施进展

2026-07-03 已更新本机 ModelPad 配置：`~/Library/Application Support/ModelPad/config.json`。

备份文件：

```text
~/Library/Application Support/ModelPad/config.json.bak-20260703-232853
```

已写入 `pdf.env`：

| 变量 | 当前值 |
|---|---|
| `PYENV_ROOT` | `/Users/jafish/.pyenv` |
| `MINERU_DEVICE_MODE` | `mps` |
| `MINERU_PDF_RENDER_THREADS` | `2` |
| `MINERU_PROCESSING_WINDOW_SIZE` | `8` |
| `MINERU_API_OUTPUT_ROOT` | `/Users/jafish/Documents/models/mineru-api-output` |
| `MINERU_API_ENABLE_FASTAPI_DOCS` | `0` |
| `MINERU_API_DISABLE_ACCESS_LOG` | `1` |
| `MINERU_API_TASK_RETENTION_SECONDS` | `21600` |

保持不变：

- `pythonScript.arguments` 仍为 `--host 127.0.0.1 --port 9000 --enable-vlm-preload False`。
- `fanyi`、`flux` 等其他模型环境变量未引入 MinerU 服务端配置。

已创建输出目录：

```text
/Users/jafish/Documents/models/mineru-api-output
```

### 阶段 1 服务级验证

已完成：

- 重新启动真实 `dist/ModelPad.app`，默认 `9786` 端口监听正常。
- 通过 ModelPad API 启动 `pdf`：
  - `POST /api/models/40621169-461C-4018-974E-9FAC92A542E7/start`
  - 返回 `status=running`，PID 为 `92833`。
- `127.0.0.1:9000` 监听正常。
- `GET http://127.0.0.1:9000/health` 返回：
  - `status=healthy`
  - `version=3.4.0`
  - `max_concurrent_requests=1`
  - `processing_window_size=8`
  - `task_retention_seconds=21600`
  - `task_cleanup_interval_seconds=300`
- `GET /docs` 返回 `404`，证明 `MINERU_API_ENABLE_FASTAPI_DOCS=0` 生效。
- ModelPad 日志中未出现健康检查请求的 uvicorn access log，符合 `MINERU_API_DISABLE_ACCESS_LOG=1` 预期。
- 通过 ModelPad API 停止 `pdf`：
  - `POST /api/models/40621169-461C-4018-974E-9FAC92A542E7/stop`
  - 返回 `status=stopped`。
- 停止后 `9000` 端口已释放。

待完成：

- 使用 `/Users/jafish/Documents/work/mineru-pdf-workflow` 的最小样本跑通一次解析。
- 验证解析完成后 `9000` 端口仍保持监听，确保没有回归到外部 workflow 误杀常驻服务。
- 验证 `MINERU_API_OUTPUT_ROOT` 指向目录产生任务输出。

## 验证方式

阶段 1 实施后至少验证：

1. ModelPad 启动 `pdf` 模型后，`127.0.0.1:9000` 正常监听。
2. 调用 `GET /health` 返回 `status=healthy`，并确认：
   - `processing_window_size` 为 `8`
   - `max_concurrent_requests` 仍为 `1`
   - `task_retention_seconds` 为 `21600`
3. `MINERU_API_OUTPUT_ROOT` 指向的目录存在，并产生任务输出。
4. ModelPad 日志中 uvicorn access log 明显减少。
5. 使用 `/Users/jafish/Documents/work/mineru-pdf-workflow` 的最小样本跑通一次解析。
6. 解析完成后 `9000` 端口仍保持监听，避免回归到外部 workflow 误杀常驻服务。
7. ModelPad 停止 `pdf` 模型后，`9000` 端口释放。

阶段 2 评估 `--enable-vlm-preload True` 时至少记录：

- 服务启动耗时。
- 首次解析耗时。
- 空闲内存占用。
- 首次解析完成后的峰值内存。

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 固定 `MINERU_PROCESSING_WINDOW_SIZE=8` 降低部分大文档吞吐 | 大 PDF 解析时间可能变长 | 先以稳定和内存峰值为优先，后续按样本调大 | 删除该 env 或恢复默认 `64` |
| 任务保留时间从 24 小时降为 6 小时 | 过期后无法通过 API 回查旧任务结果 | workflow 应保存最终输出包；需要回查时调大保留时间 | 恢复默认 `86400` 或删除该 env |
| 关闭 FastAPI docs | 本地调试 `/docs` 不可用 | 调试时临时设回 `1` | 删除 `MINERU_API_ENABLE_FASTAPI_DOCS` |
| 关闭 access log 影响排查请求 | 少了逐请求访问记录 | 出问题时临时开启 | 删除 `MINERU_API_DISABLE_ACCESS_LOG` |
| 开启 VLM 预加载后空闲内存升高 | 常驻服务占用更多内存 | 阶段 2 单独评估，不并入阶段 1 | 改回 `--enable-vlm-preload False` |

## 完成条件

阶段 1 完成条件：

- `pdf` 模型配置已包含推荐的服务端环境变量。
- 健康检查能证明 `processing_window_size`、任务保留时间等配置生效。
- 最小 PDF workflow 可跑通。
- workflow 完成后 `9000` 服务仍由 ModelPad 托管并保持监听。
- 验证证据写回本文档，并同步 `docs/PLAN_MAP.md`。

## 未决问题

| 问题 | 推荐方案 | 是否阻塞阶段 1 | 状态 |
|---|---|---|---|
| 是否开启 `--enable-vlm-preload True` | 不纳入阶段 1；阶段 2 用真实样本对比冷启动和内存 | 否 | 待评估 |
| `MINERU_PROCESSING_WINDOW_SIZE=8` 是否适合所有 PDF | 阶段 1 保持与 workflow 当前默认一致；后续按样本调优 | 否 | 待观察 |
| `MINERU_API_OUTPUT_ROOT` 是否需要进入项目输出包目录 | 不建议；API 临时任务输出与 workflow 最终输出包分离 | 否 | 已建议 |
