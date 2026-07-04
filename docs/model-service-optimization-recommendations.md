# ModelPad 模型服务优化建议汇总

日期：2026-07-04

本文汇总当前 `fanyi`、`qwen3`、`pdf` 模型服务的优化建议。本文只记录建议，不代表已修改代码或运行配置。

## 1. 当前结论

| 模型 | 当前状态 | 建议优先级 |
|---|---|---|
| `fanyi` | 使用 `mlx_lm.server`，参数主要写死在 `fanyi_server.py` 默认参数中 | P0：把启动参数迁移到 ModelPad 配置 |
| `qwen3` | 当前已使用 `qwen3_server.py`，配置中已有 `--kv-bits 8` | P1：正确接入 repetition penalty；P2：prefill / compile 基准实验 |
| `pdf` | 当前使用 `pdf_server.py` wrapper，启动后马上解析 PDF，不作为长期常驻服务 | P0：保留当前预加载和已验证窗口参数；仅修布尔解析隐患 |

## 2. fanyi 优化建议

### 2.1 P0：把启动参数迁移到 ModelPad 配置

当前 `fanyi` 的实际配置中，`pythonScript.arguments` 为空，因此启动脚本会使用 `App/Resources/Scripts/fanyi_server.py` 里的 `DEFAULT_ARGS`。这导致模型路径、端口、采样参数和 prompt cache 参数都固化在脚本里，后续调参必须改脚本。

建议把以下参数迁移到 `~/Library/Application Support/ModelPad/config.json` 的 `fanyi.pythonScript.arguments`：

```json
[
  "--model",
  "/Users/jafish/.cache/modelscope/hub/models/Tencent-Hunyuan/Hy-MT2-1.8B-4bit",
  "--host",
  "127.0.0.1",
  "--port",
  "9001",
  "--temp",
  "0.1",
  "--top-p",
  "1.0",
  "--max-tokens",
  "2048",
  "--prompt-cache-size",
  "8"
]
```

说明：

- `--temp` 建议从当前 `0.2` 降到 `0.1`，先提升翻译稳定性；如果结果仍有发挥空间，再评估 `0.0`。
- `--top-p` 建议从当前 `0.8` 调到 `1.0`，翻译任务通常不需要额外截断采样空间。
- `--top-k 20` 可先移除，减少翻译任务中的采样干预；如发现输出变差，再恢复。
- `--max-tokens 2048` 可保留，兼顾长段落翻译；如果主要翻译短文本，可再降到 `1024`。

### 2.2 P1：降低脚本职责

参数迁移后，`fanyi_server.py` 可以保留兜底默认值，但脚本职责应尽量收敛为“调用 `mlx_lm.server.main()`”。这样 ModelPad 配置才是模型启动参数的唯一主要来源。

建议验收标准：

- ModelPad UI 或配置文件中可以直接看到 `fanyi` 的模型路径、端口和采样参数。
- 修改采样参数不需要改 `fanyi_server.py`。
- 启动后仍监听 `127.0.0.1:9001`。

### 2.3 P2：按需加载和空闲卸载

如果 `fanyi` 常驻内存压力明显，可以参考 `flux_api_server.py` 的模式，封装自定义 FastAPI 服务，实现首次请求加载模型、空闲一段时间后释放模型和 MLX cache。

该项收益主要是降低空闲内存占用；代价是首次请求延迟增加，并且需要从原生 `mlx_lm.server` 迁移到自定义服务层。当前不建议作为第一步。

## 3. Qwen3 优化建议

来源：`docs/qwen3-optimization-report.md`，并结合当前实际配置校准。

### 3.1 当前已启用或基本具备

| 项目 | 当前状态 | 说明 |
|---|---|---|
| 专用服务脚本 | 已启用 | 当前配置 `scriptPath` 为 `App/Resources/Scripts/qwen3_server.py` |
| KV cache q8 量化 | 已启用 | 当前配置包含 `--kv-bits 8`；脚本默认值也是 `8` |
| 懒加载 | 已具备 | `qwen3_server.py` 在首次请求时才 `load(args.model)` |
| System prompt 透传 | 基本具备 | 请求体支持 `messages`，客户端可传 `role: "system"` |

### 3.2 P1：Repetition Penalty

当前 `qwen3_server.py` 的采样器只设置了 `temperature` 和 `top_p`。建议增加 `--repetition-penalty` 和 `--repetition-context-size` CLI 参数。

注意：本地 `mlx-lm 0.31.3` 的 `make_sampler()` 不支持 `repetition_penalty` 参数，不能写成 `make_sampler(..., repetition_penalty=...)`。正确方式是使用 `make_logits_processors()`，再传给 `generate_step(..., logits_processors=...)`。

建议默认值从 `1.05` 开始验证，必要时试 `1.1`。该项主要解决长文本输出重复、循环或自我延展问题。

### 3.3 P2：Prefill Step Size 调优

当前配置未显式传 `--prefill-step-size`，脚本默认值为 `2048`。可以在长 prompt 场景测试 `4096`，观察吞吐和内存占用。

该项无需代码改动，只需要配置参数和基准测试。

### 3.4 P3：Model Compilation

建议评估在首次推理前对模型前向或生成步骤使用 `mx.compile`。该方向成立，但不能简单理解为 `mx.compile(model)` 就能完整优化 decoding loop；当前链路包含动态 prompt、mutable cache、Python generator 和异步 eval。

建议验证方式：

- 固定同一 prompt、`max_tokens`、`temperature` 和 `top_p`。
- 对比启用前后的 tokens/s、首 token 延迟、总生成时间。
- 记录首次编译带来的额外耗时，避免把 warmup 时间混入稳定吞吐。

### 3.5 P4：Prompt Cache 复用

如果 Qwen3 存在固定 system prompt、多轮对话或 RAG 固定前缀，建议评估 prompt cache 持久化。报告预期多轮首 token 延迟可明显降低。

但 Qwen3.6 是 Gated DeltaNet + full attention 混合架构，cache 不只是标准 K/V。该项风险高于原报告描述，不建议短期直接做跨请求持久化复用；如需推进，应先做最小复现实验。

### 3.6 暂不建议：连续批处理

连续批处理更适合多用户并发服务。当前 ModelPad 是单机桌面模型托管场景，收益有限，复杂度较高，暂不建议推进。

## 4. PDF 优化建议

### 4.1 当前使用模式

当前 `pdf` 模型的实际使用模式是：服务启动后马上解析 PDF，服务退出由外部调用方统一处理，不需要 ModelPad 把它作为长期常驻服务管理。

因此当前策略成立：

```text
--enable-vlm-preload True
--idle-timeout 300
MINERU_PROCESSING_WINDOW_SIZE=8
MINERU_PDF_RENDER_THREADS=2
```

说明：

- `--enable-vlm-preload True` 适合“启动后马上解析”的场景，可以减少首次解析等待。
- `--idle-timeout 300` 表示 300 秒内没有非 `/health` 请求后，调用 `shutdown_cached_models()` 卸载 VLM 模型缓存；它不负责退出整个服务。
- 服务进程退出由外部调用方统一处理，`pdf_server.py` 不需要新增 `--exit-on-idle`。
- `MINERU_PROCESSING_WINDOW_SIZE=8` 和 `MINERU_PDF_RENDER_THREADS=2` 已经过验证，目前保持即可，不再推进窗口和线程数调参。

### 4.2 P0：修复布尔解析隐患

`pdf_server.py` 当前使用：

```python
parser.add_argument("--enable-vlm-preload", type=bool, default=False)
```

这是隐患：`argparse` 下字符串 `"False"`、`"0"` 也会被解析成 `True`。当前配置传 `True` 能符合现状，但后续如果切回 `False` 会产生错误行为。

建议后续实现时改为明确的 `str2bool` 解析，或改成 `store_true` / `store_false` 风格。

### 4.3 暂不推进的方向

- 不做 `--exit-on-idle`：退出职责由外部调用方统一处理。
- 不调整 `MINERU_PROCESSING_WINDOW_SIZE`：当前 `8` 已验证合适。
- 不调整 `MINERU_PDF_RENDER_THREADS`：当前 `2` 已验证合适。
- 不优化 `MINERU_API_MAX_CONCURRENT_REQUESTS`：MinerU 官方 FastAPI 在 macOS 下强制单并发，设置该变量没有实际收益。

## 5. 推荐执行顺序

| 顺序 | 项目 | 类型 | 原因 |
|---|---|---|---|
| 1 | `fanyi` 参数配置化 | 配置治理 | 最小改动，后续调参不再改脚本 |
| 2 | `fanyi` 翻译采样参数微调 | 质量 | 翻译任务优先稳定和忠实 |
| 3 | PDF `--enable-vlm-preload` 布尔解析修复 | 稳定性 | 当前配置可用，但存在反向配置失效隐患 |
| 4 | Qwen3 `repetition_penalty` | 质量 | 改动小，但需按正确 API 接入 |
| 5 | Qwen3 prefill step size | 性能 | 按长 prompt 场景决定是否需要 |
| 6 | Qwen3 `mx.compile` 基准评估 | 性能 | 方向成立，但必须先验证收益 |
| 7 | Qwen3 prompt cache | 性能 | hybrid cache 风险较高，暂缓 |

## 6. 验收建议

### fanyi

- 启动后 `GET /health` 或等价端口检查通过。
- 使用同一批中英互译样例，对比参数迁移前后的译文稳定性。
- 确认 `fanyi_server.py` 不再是常规调参入口。

### Qwen3

- 每项优化单独开关、单独记录测试结果。
- 至少记录：首 token 延迟、tokens/s、总耗时、峰值内存或主观内存压力。
- 质量项用固定测试集对比，避免只凭单次输出判断。

### PDF

- 启动后确认 `--enable-vlm-preload True` 语义保持不变。
- 解析完成后由外部调用方统一退出服务，ModelPad 不新增自动退出策略。
- 空闲 300 秒后仅卸载 VLM 模型缓存，不把 `/health` 计入活跃请求。
- 保持 `MINERU_PROCESSING_WINDOW_SIZE=8` 和 `MINERU_PDF_RENDER_THREADS=2`，不再重复调参。
