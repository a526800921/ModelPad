#!/usr/bin/env python3
"""
Qwen3 推理服务 — 懒加载模型 + FastAPI + 可选 KV cache 量化。

通过 make_prompt_cache 适配所有 MLX 模型架构（Qwen3.5 GatedDeltaNet +
FlashAttention 混合架构及传统 transformer），对支持标准 KVCache 的层
可开启统一精度量化（--kv-bits 8）。
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
from mlx_lm.models.cache import make_prompt_cache

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

from fastapi import FastAPI
from pydantic import BaseModel, Field

# ---------- 日志 ----------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


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

        # 打印 cache 量化策略
        if args.kv_bits:
            logger.info(
                f"KV cache quantization enabled: q{args.kv_bits}, "
                f"group_size={args.kv_group_size} "
                f"(only layers with standard KVCache)"
            )
        else:
            logger.info("KV cache quantization disabled")


# ---------- 推理 ----------
def generate_sync(prompt_tokens: list, args, cached_prompt: list):
    """同步生成 token 序列，返回完整结果。"""
    from mlx_lm.sample_utils import make_sampler

    prompt = mx.array(prompt_tokens)
    sampler = make_sampler(temp=args.temperature, top_p=args.top_p)

    # make_prompt_cache 自动适配模型架构：
    # - Qwen3.5 → model.make_cache() → ArraysCache(size=2) / KVCache
    # - 传统模型 → 标准 KVCache
    cache = make_prompt_cache(model)

    # 对支持标准 KVCache 的层开启量化（ArraysCache 层自动跳过）
    if args.kv_bits:
        quantized = 0
        for i, c in enumerate(cache):
            if hasattr(c, "to_quantized"):
                cache[i] = c.to_quantized(
                    group_size=args.kv_group_size, bits=args.kv_bits
                )
                quantized += 1
        logger.info(
            f"Quantized {quantized}/{len(cache)} cache layers to q{args.kv_bits}"
        )

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
        token_id = token.item() if hasattr(token, "item") else token
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
    parser.add_argument("--port", type=int, default=9004)

    # KV cache 量化（仅对支持标准 KVCache 的层生效）
    parser.add_argument(
        "--kv-bits", type=int, default=8,
        help="KV cache 量化 bit 数（默认 8，仅标准 KVCache 层生效）"
    )
    parser.add_argument("--kv-group-size", type=int, default=64,
                        help="量化组大小（默认 64）")

    # 推理参数
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--max-tokens", type=int, default=4096)
    parser.add_argument("--prefill-step-size", type=int, default=2048)

    args = parser.parse_args()
    app.state.args = args

    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
