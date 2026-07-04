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
import json
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
last_active = time.time()


# ---------- FastAPI ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Server starting (lazy-load mode, model loads on first request).")

    # 空闲卸载后台任务
    idle_task = asyncio.create_task(idle_unload_loop(app.state.args))

    yield

    idle_task.cancel()
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
    global model, tokenizer, last_active
    last_active = time.time()
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


async def idle_unload_loop(args):
    """后台循环：空闲超时后卸载模型释放内存。"""
    global model, tokenizer, last_active

    # 请求活动追踪中间件
    from starlette.middleware.base import BaseHTTPMiddleware

    class ActivityTracker(BaseHTTPMiddleware):
        async def dispatch(self, request, call_next):
            global last_active
            if request.url.path != "/health":
                last_active = time.time()
            return await call_next(request)

    app.add_middleware(ActivityTracker)

    while True:
        await asyncio.sleep(30)
        if model is None:
            continue
        if not hasattr(args, "idle_timeout") or args.idle_timeout <= 0:
            continue
        idle = time.time() - last_active
        if idle >= args.idle_timeout:
            async with model_lock:
                if model is None:
                    continue
                logger.info(
                    f"Idle {idle:.0f}s >= {args.idle_timeout}s, unloading model ..."
                )
                model = None
                tokenizer = None
                import gc
                gc.collect()
                logger.info("Model unloaded, memory released.")


# ---------- 推理 ----------
def generate_sync(prompt_tokens: list, args, cached_prompt: list, max_tokens: int = None):
    """同步生成 token 序列，返回完整结果。"""
    from mlx_lm.sample_utils import make_sampler, make_logits_processors

    prompt = mx.array(prompt_tokens)
    sampler = make_sampler(temp=args.temperature, top_p=args.top_p)

    # logits processors（repetition_penalty 等）
    logits_processors = make_logits_processors(
        repetition_penalty=args.repetition_penalty,
        repetition_context_size=args.repetition_context_size,
    )

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

    effective_max_tokens = max_tokens if max_tokens is not None else args.max_tokens

    generated_tokens = []
    tic = time.perf_counter()
    gen_tic = tic
    n_tokens = 0
    prefill_done = False
    last_pct = 0

    def prompt_progress(current, total):
        nonlocal last_pct
        pct = int(current / total * 100)
        if pct >= last_pct + 10:
            logger.info(f"Prompt {current}/{total} ({pct}%)")
            last_pct = pct

    for token, _ in generate_step(
        prompt,
        model,
        max_tokens=effective_max_tokens,
        sampler=sampler,
        prompt_cache=cache,
        prefill_step_size=args.prefill_step_size,
        logits_processors=logits_processors,
        prompt_progress_callback=prompt_progress,
    ):
        if not prefill_done:
            prefill_elapsed = max(time.perf_counter() - tic, 0.001)
            logger.info(
                f"Prompt processed in {prefill_elapsed:.2f}s "
                f"({len(prompt_tokens)} tokens, "
                f"{len(prompt_tokens) / prefill_elapsed:.1f} t/s)"
            )
            prefill_done = True
            gen_tic = time.perf_counter()
        token_id = token.item() if hasattr(token, "item") else token
        if token_id in tokenizer.eos_token_ids:
            break
        generated_tokens.append(token_id)
        n_tokens += 1

    gen_elapsed = max(time.perf_counter() - gen_tic, 0.001)
    logger.info(
        f"Generated {n_tokens} tokens in {gen_elapsed:.1f}s "
        f"({n_tokens / gen_elapsed:.1f} tok/s)"
    )

    return generated_tokens


def generate_stream(prompt_tokens: list, args, max_tokens: int = None):
    """流式生成 token，yield (token_id, partial_text)。"""
    from mlx_lm.sample_utils import make_sampler, make_logits_processors
    from mlx_lm.generate import generate_step

    prompt = mx.array(prompt_tokens)
    sampler = make_sampler(temp=args.temperature, top_p=args.top_p)
    logits_processors = make_logits_processors(
        repetition_penalty=args.repetition_penalty,
        repetition_context_size=args.repetition_context_size,
    )
    cache = make_prompt_cache(model)
    if args.kv_bits:
        for i, c in enumerate(cache):
            if hasattr(c, "to_quantized"):
                cache[i] = c.to_quantized(
                    group_size=args.kv_group_size, bits=args.kv_bits
                )

    effective_max_tokens = max_tokens if max_tokens is not None else args.max_tokens
    generated_ids = []
    prev_text = ""

    for token, _ in generate_step(
        prompt,
        model,
        max_tokens=effective_max_tokens,
        sampler=sampler,
        prompt_cache=cache,
        prefill_step_size=args.prefill_step_size,
        logits_processors=logits_processors,
    ):
        token_id = token.item() if hasattr(token, "item") else token
        if token_id in tokenizer.eos_token_ids:
            break
        generated_ids.append(token_id)
        full_text = tokenizer.decode(generated_ids)
        delta = full_text[len(prev_text):]
        prev_text = full_text
        yield token_id, delta


# ---------- 路由 ----------
@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": model is not None}


@app.get("/v1/models")
async def list_models():
    model_name = app.state.args.model.split("/")[-1] if app.state.args.model else "qwen3"
    return {
        "object": "list",
        "data": [
            {
                "id": model_name,
                "object": "model",
                "created": int(time.time()),
                "owned_by": "mlx",
            }
        ],
    }


def build_prompt(messages, reasoning):
    """构建 prompt token 列表。"""
    if hasattr(tokenizer, "apply_chat_template") and tokenizer.chat_template:
        template_kwargs = {}
        if reasoning == "off":
            template_kwargs["enable_thinking"] = False
        prompt_text = tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=False,
            **template_kwargs,
        )
    else:
        prompt_text = "\n".join(
            f"{m['role']}: {m['content']}" for m in messages
        ) + "\nassistant: "
    return tokenizer.encode(prompt_text)


@app.post("/v1/chat/completions")
async def chat_completions(req: ChatRequest):
    await ensure_model(app.state.args)

    messages = [m.model_dump() for m in req.messages]
    prompt_tokens = build_prompt(messages, app.state.args.reasoning)

    if req.stream:
        from starlette.responses import StreamingResponse

        async def event_stream():
            from concurrent.futures import ThreadPoolExecutor
            import queue

            q: queue.Queue = queue.Queue()
            chat_id = f"chatcmpl-{int(time.time())}"

            def run():
                try:
                    for token_id, partial_text in generate_stream(
                        prompt_tokens, app.state.args, req.max_tokens
                    ):
                        q.put(("token", token_id, partial_text))
                    q.put(("done", None, None))
                except Exception as e:
                    q.put(("error", str(e), None))

            loop = asyncio.get_event_loop()
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = loop.run_in_executor(pool, run)

                while True:
                    try:
                        item = await loop.run_in_executor(None, q.get, True, 0.1)
                    except queue.Empty:
                        continue

                    kind = item[0]
                    if kind == "done":
                        chunk = {
                            "id": chat_id,
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": app.state.args.model.split("/")[-1],
                            "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                        }
                        yield f"data: {json.dumps(chunk)}\n\n"
                        yield "data: [DONE]\n\n"
                        break
                    elif kind == "token":
                        _, token_id, partial_text = item
                        chunk = {
                            "id": chat_id,
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": app.state.args.model.split("/")[-1],
                            "choices": [{"index": 0, "delta": {"content": partial_text}, "finish_reason": None}],
                        }
                        yield f"data: {json.dumps(chunk)}\n\n"
                    elif kind == "error":
                        yield f"data: {json.dumps({'error': item[1]})}\n\n"
                        break

                await future

        return StreamingResponse(
            event_stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "Connection": "keep-alive"},
        )

    # 非流式
    from concurrent.futures import ThreadPoolExecutor

    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor(max_workers=1) as pool:
        generated = await loop.run_in_executor(
            pool,
            generate_sync,
            prompt_tokens,
            app.state.args,
            [],
            req.max_tokens,
        )

    completion_text = tokenizer.decode(generated)

    return ChatResponse(
        id=f"chatcmpl-{int(time.time())}",
        created=int(time.time()),
        model=app.state.args.model.split("/")[-1],
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

    # 惩罚参数（通过 logits_processors 生效）
    parser.add_argument("--repetition-penalty", type=float, default=1.05,
                        help="重复惩罚系数（默认 1.05，1.0 为不惩罚）")
    parser.add_argument("--repetition-context-size", type=int, default=20,
                        help="重复惩罚窗口大小（默认 20）")

    # 思考模式
    parser.add_argument("--reasoning", default="auto",
                        choices=["on", "off", "auto"],
                        help="思考/推理模式（默认 auto）")

    # 空闲回收
    parser.add_argument("--idle-timeout", type=int, default=300,
                        help="空闲超时自动卸载模型（秒），0 表示不卸载（默认 300）")

    args = parser.parse_args()
    app.state.args = args

    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
