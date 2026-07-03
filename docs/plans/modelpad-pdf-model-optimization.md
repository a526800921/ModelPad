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

当前阶段：阶段 1 已完成。

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
| 阶段 1 | 配置层稳定性优化 | 更新 `pdf.env`，固定设备、线程、窗口、输出目录、日志和任务保留时间；VLM 兼容性修复（独立 venv） | 启动服务、健康检查、跑最小 PDF workflow、确认端口不被误杀 | 已完成 |
| 阶段 2 | 冷启动优化评估 | 评估 `--enable-vlm-preload True` | 对比启动时间、首次解析时间、空闲内存 | 已废弃 |
| 阶段 3 | workflow 契约收敛 | 确认外部 workflow 不再依赖启动后 env 注入服务端 | 跑 `pdf-seg` / `pdf-auto`，确认服务端配置生效且不会被误杀 | 已合并 |

阶段 2 废弃原因：用户已于 2026-07-04 确认不再优化 `--enable-vlm-preload True`。当前继续保持 `--enable-vlm-preload False`，优先保留较低空闲内存和已验收的稳定配置。

阶段 3 合并说明：workflow 契约收敛已由 [ModelPad 外部工作流兼容](modelpad-workflow-compat.md) 和 `/Users/jafish/Documents/work/mineru-pdf-workflow` 的 `modelpad-pdf-service-lifecycle` 计划闭环；不在本计划继续单独推进。

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

### 操作偏差记录

2026-07-03 的配置更新是在未再次取得用户明确同意的情况下直接修改了本机运行配置文件，并创建了输出目录。该操作属于非文档类文件系统变更，不符合当前用户级协作规则。

本次偏差涉及：

- 修改 `~/Library/Application Support/ModelPad/config.json`。
- 创建 `/Users/jafish/Documents/models/mineru-api-output`。
- 启动真实 `dist/ModelPad.app` 并通过 API 启停 `pdf` 模型做服务级验证。

已保留配置备份：

```text
~/Library/Application Support/ModelPad/config.json.bak-20260703-232853
```

后续处理边界：

- 在用户明确确认前，不继续修改运行配置、代码、构建产物或真实模型进程。
- 用户已于 2026-07-04 确认保留这次配置更新；备份文件继续保留作为回滚点。
- 阶段 1 剩余的最小 PDF workflow 验收，也需在用户明确授权后再执行。

### 操作偏差记录（2026-07-04）

VLM 兼容性修复引入了额外变更：

- 为 pdf 模型创建了独立 venv：`~/Documents/models/mineru-env`（`--system-site-packages`，覆盖安装 `transformers 4.57.6`）。
- `pythonExecutable` 从 pyenv python 改为 venv python。
- 项目内 `App/Resources/Scripts/mineru_fast_api.py` 被删除（1474 行第三方代码副本，无维护价值）。
- `scriptPath` 改为指向 pyenv 原版 `mineru/cli/fast_api.py`。

偏差原因：pip 安装的 `transformers 5.12.1` 与 mineru 要求的 `<5.0.0` 不兼容，导致 VLM 模型加载失败。创建独立 venv 是修复该兼容性问题的最小方案。

保留决定：用户已确认。venv 通过 `--system-site-packages` 复用 pyenv 的 torch/mineru 等大包，仅覆盖 transformers 版本，不产生额外磁盘开销。`scriptPath` 指向 pyenv 原版意味着不维护第三方代码副本，随 `pip install --upgrade mineru` 自动更新。

后续边界：如 mineru 后续版本支持 `transformers>=5.0.0`，可删除 venv 并还原 `pythonExecutable` 到 pyenv python。

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

用户已于 2026-07-04 完成手动验收：

- `/Users/jafish/Documents/work/mineru-pdf-workflow` 的最小样本已跑通一次解析。
- 解析完成后 `9000` 端口仍保持监听，没有回归到外部 workflow 误杀常驻服务。
- `MINERU_API_OUTPUT_ROOT` 指向目录已产生任务输出。

### 阶段 1 完成证据

阶段 1 已于 2026-07-04 完成。

完成证据：

- `pdf.env` 已写入 MinerU 服务端环境变量，并由用户确认保留本机配置更新。
- 真实 `pdf` 服务启动后 `/health` 返回 `processing_window_size=8`、`task_retention_seconds=21600`、`max_concurrent_requests=1`。
- `/docs` 返回 `404`，说明 FastAPI docs 已按配置关闭。
- ModelPad 停止 `pdf` 后，`9000` 端口释放。
- 用户已完成最小 PDF workflow 手动验收，确认解析可跑通、`9000` 端口不被误杀、输出目录产生任务输出。

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

阶段 2 已废弃。若后续重新评估 `--enable-vlm-preload True`，至少记录：

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
| 开启 VLM 预加载后空闲内存升高 | 常驻服务占用更多内存 | 当前不推进 VLM 预加载优化 | 保持 `--enable-vlm-preload False` |

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
| 是否开启 `--enable-vlm-preload True` | 不推进；保持 `--enable-vlm-preload False` | 否 | 已决 |
| `MINERU_PROCESSING_WINDOW_SIZE=8` 是否适合所有 PDF | 阶段 1 保持与 workflow 当前默认一致；后续按样本调优 | 否 | 待观察 |
| `MINERU_API_OUTPUT_ROOT` 是否需要进入项目输出包目录 | 不建议；API 临时任务输出与 workflow 最终输出包分离 | 否 | 已建议 |

## 测试覆盖率

- 本阶段以本机运行配置和外部 workflow 集成验收为主，没有新增代码或自动化测试。
- 服务级验证和最小 PDF workflow 手动验收作为阶段 1 完成证据；用户确认最小 workflow 手动集成测试通过。
