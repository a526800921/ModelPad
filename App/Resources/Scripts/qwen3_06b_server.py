#!/usr/bin/env python3
"""
Qwen3-0.6B-MLX-4bit 推理服务 — 轻量版，专为 0.6B 小模型。
懒加载 + FastAPI + OpenAI 兼容 /v1/chat/completions。
"""

import os
import argparse
import asyncio
import time
import json
import logging
import uuid
from contextlib import asynccontextmanager
from typing import Optional

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ---------- 日志 ----------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("qwen3-0.6b")


# ---------- 全局 ----------
model = None
tokenizer = None
model_lock = asyncio.Lock()


# ---------- FastAPI ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Server starting (lazy-load mode).")
    yield
    logger.info("Server shutting down.")


app = FastAPI(title="Qwen3-0.6B Chat API", lifespan=lifespan)


class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]
    max_tokens: int = Field(default=512, ge=1, le=4096)
    temperature: float = Field(default=0.0, ge=0.0, le=2.0)
    top_p: float = Field(default=1.0, ge=0.0, le=1.0)


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
    choices: list[ChatChoice]
    usage: Usage


# ---------- 模型加载 ----------
async def ensure_model(args):
    global model, tokenizer

    if model is not None:
        return

    async with model_lock:
        if model is not None:
            return

        import mlx.core as mx
        from mlx_lm import load

        logger.info(f"Loading model from {args.model} ...")
        t0 = time.time()
        model, tokenizer = load(args.model, tokenizer_config={})
        logger.info(f"Model loaded in {time.time() - t0:.1f}s")


# ---------- 推理 ----------
def generate_sync(prompt_tokens: list, args, max_tokens: int):
    """同步生成，返回 token 列表。"""
    import mlx.core as mx
    from mlx_lm.sample_utils import make_sampler
    from mlx_lm.models.cache import make_prompt_cache
    from mlx_lm.generate import generate_step

    prompt = mx.array(prompt_tokens)
    sampler = make_sampler(temp=args.temperature, top_p=args.top_p)
    cache = make_prompt_cache(model)

    generated = []
    prefill_done = False
    tic = time.perf_counter()

    for token, _ in generate_step(
        prompt,
        model,
        max_tokens=max_tokens,
        sampler=sampler,
        prompt_cache=cache,
        prefill_step_size=args.prefill_step_size,
    ):
        if not prefill_done:
            elapsed = max(time.perf_counter() - tic, 0.001)
            logger.info(
                f"Prompt {len(prompt_tokens)} tokens in {elapsed:.2f}s "
                f"({len(prompt_tokens) / elapsed:.0f} t/s)"
            )
            prefill_done = True
            tic = time.perf_counter()

        token_id = token.item() if hasattr(token, "item") else token
        if token_id in tokenizer.eos_token_ids:
            break
        generated.append(token_id)

    elapsed = max(time.perf_counter() - tic, 0.001)
    n = len(generated)
    if n > 0:
        logger.info(f"Generated {n} tokens in {elapsed:.1f}s ({n / elapsed:.1f} t/s)")

    return generated


def build_prompt(messages: list[dict]) -> list[int]:
    """构建 prompt token 列表。"""
    if hasattr(tokenizer, "apply_chat_template") and tokenizer.chat_template:
        prompt_text = tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=False,
            enable_thinking=False,
        )
    else:
        prompt_text = "\n".join(
            f"{m['role']}: {m['content']}" for m in messages
        ) + "\nassistant: "
    return tokenizer.encode(prompt_text)


# ---------- 路由 ----------
@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": model is not None}


@app.post("/v1/chat/completions")
async def chat_completions(req: ChatRequest):
    await ensure_model(app.state.args)

    messages = [m.model_dump() for m in req.messages]
    prompt_tokens = build_prompt(messages)

    from concurrent.futures import ThreadPoolExecutor

    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor(max_workers=1) as pool:
        generated = await loop.run_in_executor(
            pool,
            generate_sync,
            prompt_tokens,
            app.state.args,
            req.max_tokens,
        )

    completion_text = tokenizer.decode(generated)

    return ChatResponse(
        id=f"chatcmpl-{uuid.uuid4().hex[:24]}",
        created=int(time.time()),
        model="qwen3-0.6b",
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
    parser = argparse.ArgumentParser(description="Qwen3-0.6B Chat Server")
    parser.add_argument(
        "--model",
        default=os.path.expanduser(
            "~/.cache/modelscope/hub/models/Qwen/Qwen3-0___6B-MLX-4bit"
        ),
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9006)
    parser.add_argument("--temperature", type=float, default=0.1)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--max-tokens", type=int, default=2048)
    parser.add_argument("--prefill-step-size", type=int, default=2048)

    args = parser.parse_args()
    app.state.args = args

    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
