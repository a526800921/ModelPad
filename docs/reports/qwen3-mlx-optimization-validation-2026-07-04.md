# Qwen3.6 MLX 优化建议正确性核实

日期：2026-07-04

核实对象：

- `docs/qwen3-optimization-report.md`
- `docs/model-service-optimization-recommendations.md`
- 当前 `qwen3` 运行配置：`~/Library/Application Support/ModelPad/config.json`
- 当前脚本：`App/Resources/Scripts/qwen3_server.py`

外部核实来源：

- Qwen 官方模型卡：<https://huggingface.co/Qwen/Qwen3.6-35B-A3B>
- MLX Community 模型卡：<https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit>
- MLX 编译文档：<https://ml-explore.github.io/mlx/build/html/usage/compile.html>
- mlx-lm 当前源码：<https://github.com/ml-explore/mlx-lm>
- QwenLM 相关 MLX cache issue：<https://github.com/QwenLM/Qwen3.6/issues/37>

## 1. 总体结论

原建议中，模型架构判断、当前配置状态、KV cache q8 量化方向基本正确；但部分实施建议需要修正优先级和实现方式。

最需要修正的点：

1. `repetition_penalty` 不能直接传给 `make_sampler`。当前本地 `mlx-lm 0.31.3` 的 `make_sampler` 不支持该参数，应通过 `make_logits_processors()` 生成 logits processors，再传给 `generate_step(..., logits_processors=...)`。
2. `Prompt Cache 复用` 对 Qwen3.6 这类 Gated DeltaNet + full attention 混合架构不应标为低风险。MLX/MLX-LM 生态中仍有 hybrid prompt cache 复用相关问题和修复讨论，建议降级为实验项。
3. `mx.compile` 建议方向成立，但原报告的“约 10 行、极低风险、20-40% 提速”表述过满。当前脚本中的生成路径包含可变长度 prompt、状态化 cache、Python generator 和异步 eval，不能简单 `mx.compile(model)` 就视为完成优化。

## 2. 逐项核实

| 优化项 | 原建议判断 | 核实结论 | 修正建议 |
|---|---|---|---|
| Qwen3.6 架构：40 层，30 个 Gated DeltaNet，10 个 full attention | 正确 | 官方模型卡给出 `10 × (3 × Gated DeltaNet + 1 × Gated Attention)`；本地 config 的 `layer_types` 也是每 4 层 3 个 linear + 1 个 full | 保留 |
| 35B 总参数、3B 激活参数 | 正确 | 官方模型卡一致 | 保留 |
| 当前使用 `qwen3_server.py` | 正确 | 当前配置 `scriptPath` 已指向 `qwen3_server.py` | 保留 |
| 当前启用 `--kv-bits 8` | 正确 | 当前配置中已有 `--kv-bits`, `"8"`；脚本默认值也是 8 | 保留 |
| KV cache q8 只作用于标准 KVCache 层 | 基本正确 | 本地 `qwen3_5.py` 的 `make_cache()` 对 linear 层返回 `ArraysCache(size=2)`，full attention 层返回 `KVCache()`；脚本只量化有 `to_quantized` 的 cache | 保留，但说明“仅 full attention KVCache 层” |
| q8 KV cache 显存降低约 50% 且不影响精度 | 表述偏强 | q8 相对 BF16 KV 通常会明显省内存，但有 scale/metadata 开销；“不影响精度”应改成“预计影响较小，需样例验证” | 改成保守表述 |
| `mx.compile` | 方向成立，收益未证实 | MLX 支持函数编译并可能改善运行时和内存，但当前生成链路不是简单纯函数；直接 `mx.compile(model)` 不等于编译完整 decoding loop | 降为 P1 实验项，先做基准 |
| Prompt Cache 复用 | 风险被低估 | `save_prompt_cache`/`load_prompt_cache` API 存在，但 Qwen3.5/3.6 hybrid cache 复用有公开问题；当前脚本每次请求新建 cache，没有跨请求复用 | 降为 P3 实验项 |
| Prefill Step Size 调优 | 正确 | `generate_step` 支持 `prefill_step_size`，当前默认 2048；可通过配置测试 4096 | 保留为低成本实验 |
| Repetition Penalty | 功能方向正确，实现方式错误 | `make_sampler()` 不支持 `repetition_penalty`；`make_logits_processors()` 支持 | 改为新增 CLI 参数并接入 logits processors |
| System Prompt 透传 | 正确 | `ChatRequest.messages` 支持 system 消息，脚本使用 tokenizer chat template | 保留 |
| 连续批处理暂不建议 | 正确 | 当前 ModelPad 是本地单用户托管，复杂度大于收益 | 保留 |

## 3. 建议后的优先级

### P0：先修正可观测性和参数面

- 在日志中输出 `mlx-lm` 版本、模型路径、`kv_bits`、`prefill_step_size`、采样参数。
- 保留当前 `--kv-bits 8`，但增加固定测试样例验证 q8 与无 KV 量化的输出质量差异。

### P1：接入 repetition penalty，但按正确 API 实现

建议增加：

- `--repetition-penalty`
- `--repetition-context-size`

实现方向：

```python
from mlx_lm.sample_utils import make_sampler, make_logits_processors

sampler = make_sampler(temp=args.temperature, top_p=args.top_p)
logits_processors = make_logits_processors(
    repetition_penalty=args.repetition_penalty,
    repetition_context_size=args.repetition_context_size,
)

generate_step(
    prompt,
    model,
    sampler=sampler,
    logits_processors=logits_processors,
    ...
)
```

初始建议值：

- `repetition_penalty = 1.05`
- `repetition_context_size = 64` 或 `128`

注意：如果 `temperature=0.0` 是贪心解码，repetition penalty 仍可能改变 argmax 结果；需要用固定长文本样例验证。

### P2：Prefill Step Size 基准测试

当前 `prefill_step_size=2048`。可以只改配置测试：

- `2048`
- `4096`
- 视内存情况再测 `8192`

记录：

- prompt tokens
- prompt prefill 耗时
- generation tokens/s
- 峰值内存或主观内存压力

### P3：`mx.compile` 实验，不建议直接按原报告实施

正确姿势不是简单写：

```python
mx.compile(model)
```

更合理的实验方向：

- 找到稳定的 `_model_call` 或单 token `_step` 函数边界。
- 避免把 Python generator、cache 创建、tokenizer、HTTP 层放进编译目标。
- 固定输入形状做 warmup，单独记录首次编译耗时。
- 对比 warmup 后的 tokens/s。

只有基准数据证明收益后，再把它升为常规优化。

### P4：Prompt Cache 复用暂缓

不建议现在实现跨请求 prompt cache 持久化。原因：

- Qwen3.6 是 hybrid 架构，cache 不只是标准 K/V。
- 本地 MLX-LM 已有 `ArraysCache` 与 `KVCache` 混合 cache。
- 公开 issue 显示 hybrid prompt cache 复用曾导致 prefill 或多轮复用问题。

如果后续要做，应先做最小实验：

1. 固定 system prompt。
2. 保存 cache。
3. 加载 cache 后生成同一问题。
4. 对比不复用 cache 的输出、耗时和异常率。

## 4. 需要同步修正文档的地方

建议修改 `docs/qwen3-optimization-report.md`：

- 把 `Model Compilation` 从“立即实施 P0”改为“P3 实验项，需基准确认”。
- 把 `Repetition Penalty` 的示例改成 `make_logits_processors()`，不要写成 `make_sampler(..., repetition_penalty=...)`。
- 把 `Prompt Cache 复用` 从“低风险”改成“对 hybrid 架构风险中等，需要最小复现实验”。
- 把 “q8 KV cache 不影响精度” 改成 “预计质量影响较小，但需固定样例验证”。

建议修改 `docs/model-service-optimization-recommendations.md`：

- Qwen3 推荐顺序改为：
  1. 保留并验证 `--kv-bits 8`
  2. 正确接入 `repetition_penalty`
  3. 测试 `prefill_step_size`
  4. 实验 `mx.compile`
  5. 暂缓 prompt cache 复用

