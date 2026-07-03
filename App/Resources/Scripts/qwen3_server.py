#!/usr/bin/env python3
"""
Qwen3 专用推理服务 — 支持 K q8 / V q4 混合精度 KV Cache 量化。

基于 MLX mlx_lm.server 架构，增加自定义 QuantizedKVCache 以支持
K/V 不同量化精度，同时复用 mlx_lm 的模型加载和 tokenizer。
"""

import os
import argparse
import asyncio
import time
import logging
from contextlib import asynccontextmanager
from typing import Optional, List, Dict, Any

import mlx.core as mx
import mlx.nn as nn
from mlx_lm import load
from mlx_lm.tokenizer_utils import TokenizerWrapper
from mlx_lm.models.cache import make_prompt_cache, QuantizedKVCache, KVCache

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

from fastapi import FastAPI
from pydantic import BaseModel, Field

# ---------- 日志 ----------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ---------- 自定义 K/V 混合精度量化 Cache ----------
class MixedQuantizedKVCache:
    """支持 K 和 V 使用不同 bit 宽度的量化 KV Cache。"""

    def __init__(self, group_size: int = 64, k_bits: int = 8, v_bits: int = 4):
        self.keys = None
        self.values = None
        self.offset = 0
        self.group_size = group_size
        self.k_bits = k_bits
        self.v_bits = v_bits

    @classmethod
    def from_cache(
        cls, cache, group_size: int = 64, k_bits: int = 8, v_bits: int = 4
    ):
        """从普通 KVCache 创建混合精度量化 cache。"""
        q = cls(group_size=group_size, k_bits=k_bits, v_bits=v_bits)
        q.offset = cache.offset
        if cache.keys is not None:
            q.keys = mx.quantize(cache.keys, group_size=group_size, bits=k_bits)
            q.values = mx.quantize(cache.values, group_size=group_size, bits=v_bits)
        return q


def make_mixed_quantized_cache(
    model: nn.Module,
    k_bits: int = 8,
    v_bits: int = 4,
    group_size: int = 64,
    quantized_kv_start: int = 0,
) -> list:
    """创建混合精度 KV cache，前 quantized_kv_start 层不量化。"""
    num_layers = len(model.layers)
    caches = []
    for i in range(num_layers):
        if i < quantized_kv_start:
            caches.append(KVCache())
        else:
            caches.append(
                MixedQuantizedKVCache(
                    group_size=group_size, k_bits=k_bits, v_bits=v_bits
                )
            )
    return caches


# ---------- 全局 ----------
model = None
tokenizer = None
model_lock = asyncio.Lock()

# ---------- FastAPI ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Server starting (lazy-load mode, model loads on first request).")
    yield
    logger.info("Server shutting down.")


app = FastAPI(title="Qwen3 Chat API", lifespan=lifespan)


class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: List[Message]
    max_tokens: int = Field(default=512, ge=1, le=16384)
    temperature: float = Field(default=0.0, ge=0.0, le=2.0)
    top_p: float = Field(default=1.0, ge=0.0, le=1.0)
    stream: bool = False


class ChatChoice(BaseModel):
    index: int = 0
    message: Message
    finish_reason: Optional[str] = None


class Usage(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


class ChatResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[ChatChoice]
    usage: Usage


# ---------- 模型加载 ----------
async def ensure_model(args):
    global model, tokenizer
    if model is not None:
        return
    async with model_lock:
        if model is not None:
            return
        logger.info(f"Loading model from {args.model} ...")
        t0 = time.time()
        model, tokenizer = load(args.model, tokenizer_config={})
        logger.info(f"Model loaded in {time.time() - t0:.1f}s")

        # 日志打印 cache 量化策略
        if args.kv_k_bits and args.kv_v_bits:
            logger.info(
                f"KV cache quantization: K q{args.kv_k_bits} / V q{args.kv_v_bits}, "
                f"group_size={args.kv_group_size}, "
                f"quantize from layer {args.quantized_kv_start}"
            )
        elif args.kv_bits:
            logger.info(
                f"KV cache quantization: K/V q{args.kv_bits}, "
                f"group_size={args.kv_group_size}"
            )


# ---------- 推理 ----------
def generate_sync(prompt_tokens: list, args, cached_prompt: list):
    """同步生成 token 序列，返回完整结果。"""
    from mlx_lm.sample_utils import make_sampler

    prompt = mx.array(prompt_tokens)
    sampler = make_sampler(temp=args.temperature, top_p=args.top_p)

    # 创建 KV cache
    if args.kv_k_bits and args.kv_v_bits:
        cache = make_mixed_quantized_cache(
            model,
            k_bits=args.kv_k_bits,
            v_bits=args.kv_v_bits,
            group_size=args.kv_group_size,
            quantized_kv_start=args.quantized_kv_start,
        )
    elif args.kv_bits:
        cache = make_prompt_cache(model)
        # 立即量化
        for i, c in enumerate(cache):
            if i >= args.quantized_kv_start and hasattr(c, "to_quantized"):
                cache[i] = c.to_quantized(
                    group_size=args.kv_group_size, bits=args.kv_bits
                )
    else:
        cache = make_prompt_cache(model)

    # 前向传播
    from mlx_lm.generate import generate_step

    generated_tokens = []
    tic = time.perf_counter()
    n_tokens = 0

    for token, _ in generate_step(
        prompt,
        model,
        max_tokens=args.max_tokens,
        sampler=sampler,
        prompt_cache=cache,
        prefill_step_size=args.prefill_step_size,
    ):
        token_id = token.item()
        if token_id in tokenizer.eos_token_ids:
            break
        generated_tokens.append(token_id)
        n_tokens += 1

    elapsed = time.perf_counter() - tic
    logger.info(
        f"Generated {n_tokens} tokens in {elapsed:.1f}s "
        f"({n_tokens / elapsed:.1f} tok/s)"
    )

    return generated_tokens


# ---------- 路由 ----------
@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": model is not None}


@app.post("/v1/chat/completions", response_model=ChatResponse)
async def chat_completions(req: ChatRequest):
    await ensure_model(app.state.args)

    # 构建 chat template prompt
    if hasattr(tokenizer, "apply_chat_template") and tokenizer.chat_template:
        prompt_text = tokenizer.apply_chat_template(
            [m.model_dump() for m in req.messages],
            add_generation_prompt=True,
            tokenize=False,
        )
    else:
        prompt_text = "\n".join(
            f"{m.role}: {m.content}" for m in req.messages
        ) + "\nassistant: "

    prompt_tokens = tokenizer.encode(prompt_text)

    # 推理
    from concurrent.futures import ThreadPoolExecutor

    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor(max_workers=1) as pool:
        generated = await loop.run_in_executor(
            pool,
            generate_sync,
            prompt_tokens,
            app.state.args,
            [],
        )

    completion_text = tokenizer.decode(generated)

    return ChatResponse(
        id=f"chatcmpl-{int(time.time())}",
        created=int(time.time()),
        model=app.state.args.model,
        choices=[
            ChatChoice(
                index=0,
                message=Message(role="assistant", content=completion_text),
                finish_reason="stop",
            )
        ],
        usage=Usage(
            prompt_tokens=len(prompt_tokens),
            completion_tokens=len(generated),
            total_tokens=len(prompt_tokens) + len(generated),
        ),
    )


# ---------- 主入口 ----------
def main():
    parser = argparse.ArgumentParser(description="Qwen3 Chat Server")
    parser.add_argument(
        "--model",
        default=os.path.expanduser(
            "~/.cache/modelscope/hub/models/mlx-community/Qwen3.6-35B-A3B-4bit"
        ),
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8790)

    # KV cache 量化
    parser.add_argument("--kv-bits", type=int, default=None,
                        help="KV cache 统一量化 bit 数 (K=V)")
    parser.add_argument("--kv-k-bits", type=int, default=8,
                        help="K cache 量化 bit 数 (默认 8)")
    parser.add_argument("--kv-v-bits", type=int, default=4,
                        help="V cache 量化 bit 数 (默认 4)")
    parser.add_argument("--kv-group-size", type=int, default=64)
    parser.add_argument("--quantized-kv-start", type=int, default=0)

    # 推理参数
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--max-tokens", type=int, default=4096)
    parser.add_argument("--prefill-step-size", type=int, default=2048)

    args = parser.parse_args()

    # 如果只设了 --kv-bits，则 K=V；否则用独立的 k/v bits
    if args.kv_bits is not None:
        args.kv_k_bits = args.kv_bits
        args.kv_v_bits = args.kv_bits

    app.state.args = args

    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
