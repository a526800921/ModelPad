# Qwen3.6-35B-A3B 优化分析报告

**日期**: 2026-07-04  
**模型**: Qwen3.6-35B-A3B-4bit (MLX Community)  
**引擎**: MLX 0.31.2 / Apple Metal GPU  
**当前端口**: 9004  
**服务脚本**: `qwen3_server.py`

---

## 1. 当前配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| 模型路径 | `mlx-community/Qwen3.6-35B-A3B-4bit` | 4-bit 量化权重 |
| 精度 | Q4 (约 18-20GB 显存) | 35B MoE, 3B 激活参数 |
| KV Cache | q8 (仅 10 个 Full Attention 层) | 30 个 GatedDeltaNet 层走 ArraysCache，不量化 |
| max_tokens | 4096 | |
| temperature | 0.0 | 贪心解码 |
| prefill_step_size | 2048 | |
| 启动模式 | 懒加载 (首请求触发) | |

---

## 2. 已验证的优化

### 2.1 q8 KV Cache 量化 (已生效)

- **原理**: Qwen3.5 使用 GatedDeltaNet + FlashAttention 混合架构。40 层中 30 个线性注意力层走 `ArraysCache(size=2)`，10 个标准注意力层走 `KVCache`
- **做法**: 对 10 个 `KVCache` 层调用 `to_quantized(bits=8)`，`ArraysCache` 层自动跳过 (`hasattr` 检测)
- **效果**: 标准 attention 层的 KV cache 显存占用降低约 50%，不影响精度
- **验证日志**: `Quantized 10/40 cache layers to q8`

### 2.2 本地服务架构

- 相比通用的 `mlx_lm_server.py` (委托 `mlx_lm.server.main()`)，`qwen3_server.py` 自建 FastAPI + `generate_step` 循环，提供了更可控的推理链路，便于后续优化注入

---

## 3. 速率优化

### 3.1 Model Compilation (`mx.compile`) ★★★ 推荐

| 属性 | 说明 |
|------|------|
| 预期收益 | 20-40% tokens/s 提升 |
| 改动量 | ~10 行代码 |
| 风险 | 极低 (MLX 已验证) |
| 原理 | 编译 `generate_step` 中的模型前向传播为 Metal kernel，消除 Python 开销 |

**实现**: 在首次推理前调用 `mx.compile()` 编译模型或 step 函数：

```python
import mlx.core as mx

# 编译模型前向传播 (warmup)
mx.compile(model)
# 或者更精细地编译 generate_step 内部循环
```

### 3.2 Prompt Cache 复用 ★★

| 属性 | 说明 |
|------|------|
| 预期收益 | 多轮对话首 token 延迟降低 80%+ |
| 改动量 | 中等 (~50 行) |
| 风险 | 低 |
| 原理 | 将 system prompt 的 KV cache 预计算并持久化。后续对话直接加载，跳过 prefill |

**适用场景**: 固定 system prompt 的多轮对话、RAG 场景复用文档前缀。

MLX 已提供 `save_prompt_cache` / `load_prompt_cache` API：

```python
from mlx_lm.models.cache import save_prompt_cache, load_prompt_cache

# 首次：计算并保存
cache = make_prompt_cache(model)
# ... 处理 system prompt ...
save_prompt_cache("system_cache.safetensors", cache, {})

# 后续：加载复用
cache = load_prompt_cache("system_cache.safetensors")
```

### 3.3 Prefill Step Size 调优 ★

| 属性 | 说明 |
|------|------|
| 预期收益 | 5-15% 长 prompt 吞吐提升 |
| 改动量 | 无 (已有 CLI 参数) |
| 风险 | 显存增加 |
| 当前值 | 2048 |

可测试 `--prefill-step-size 4096` 或更大值，观察显存和速度变化。

### 3.4 连续批处理 (Continuous Batching)

| 属性 | 说明 |
|------|------|
| 预期收益 | 多用户并发时吞吐翻倍 |
| 改动量 | 大 |
| 风险 | 中 |
| 适用性 | 当前为单用户桌面应用，暂不推荐 |

---

## 4. 准确率优化

### 4.1 System Prompt ★★

| 属性 | 说明 |
|------|------|
| 预期收益 | 角色一致性、回答质量明显提升 |
| 改动量 | 小 (API 层透传) |

当前 `ChatRequest` 已支持 `messages` 数组，只需客户端在消息列表中加入 `role: "system"` 的消息即可。

### 4.2 Repetition Penalty ★★

| 属性 | 说明 |
|------|------|
| 预期收益 | 解决长文本生成时的重复/循环问题 |
| 改动量 | 小 (~5 行) |

MLX 的 `make_sampler` 支持 `repetition_penalty` 参数。当前未设置，默认为 1.0 (不惩罚)。建议设为 1.05-1.1。

```python
sampler = make_sampler(
    temp=args.temperature,
    top_p=args.top_p,
    repetition_penalty=args.repetition_penalty,  # 新增参数
)
```

### 4.3 模型量化精度 ★

| 精度 | 显存占用 (估算) | 准确率 | 可行性 |
|------|----------------|--------|--------|
| Q4 (当前) | ~20GB | 基准 | ✓ 已在使用 |
| Q6 | ~28GB | 提升 1-3% | M3 Max 64GB 可试 |
| Q8 | ~36GB | 提升 3-5% | 需 64GB+ 机型 |

Q4 对 35B MoE 模型来说是合理的平衡点——3B 激活参数 + 量化，质量损失在可控范围。

### 4.4 Thinking/Reasoning Token 控制

Qwen3 默认开启思考模式，生成大量 `<think>` 内部推理 token。从测试看，回答一句话也需要 ~470 思考 token。如果不需要链式思考，可以在 tokenizer 层面控制，但该功能依赖模型的 `chat_template` 配置，当前 Qwen3.6 社区版未暴露此开关。

---

## 5. 推荐实施优先级

| 优先级 | 优化项 | 分类 | 改动量 | 预期收益 |
|--------|--------|------|--------|----------|
| P0 | Model Compilation | 速率 | 小 | 20-40% 提速 |
| P1 | Repetition Penalty | 准确率 | 小 | 防重复循环 |
| P1 | System Prompt 透传 | 准确率 | 小 | 回答质量 |
| P2 | Prompt Cache 复用 | 速率 | 中 | 多轮首 token 大幅加速 |
| P3 | Prefill Step Size | 速率 | 无 | 长 prompt 吞吐 |
| - | 连续批处理 | 速率 | 大 | 暂不需要 |

---

## 6. 下一步

1. **立即**: 实施 P0 (model compilation)，基准测试对比 tokens/s
2. **立即**: 实施 P1 (repetition penalty + system prompt)，质量对比
3. **短期**: 评估 P2 (prompt cache) 对多轮对话的收益
