#!/usr/bin/env python3
"""
FLUX.1-dev 文生图 FastAPI 服务
- T5/CLIP: 全精度 (不可量化，否则语义退化)
- Transformer/VAE: 4-bit 量化
- 空闲超时自动卸载：推理完成后启动 5 分钟空闲定时器，超时卸载模型释放显存，下次请求按需重载
"""

import os
import io
import gc
import base64
import random
import time
import logging
import asyncio
import mlx.core
from pathlib import Path
from contextlib import asynccontextmanager

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from mflux.models.common.config.model_config import ModelConfig
from mflux.models.flux.variants.txt2img.flux import Flux1

# ---------- 配置 ----------
MODEL_PATH = os.path.expanduser("~/.cache/modelscope/hub/models/AI-ModelScope/FLUX___1-dev/")
OUTPUT_DIR = os.path.expanduser("~/Documents/models/output/")
QUANTIZE = 4
IDLE_TIMEOUT = 5  # 空闲超时秒数，超时后卸载模型释放显存

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

flux_model: Flux1 | None = None
model_lock = asyncio.Lock()
_idle_timer_task: asyncio.Task | None = None


def _cancel_idle_timer():
    """取消当前空闲定时器（如果有）。"""
    global _idle_timer_task
    if _idle_timer_task is not None and not _idle_timer_task.done():
        _idle_timer_task.cancel()
        _idle_timer_task = None


def _start_idle_timer():
    """启动空闲定时器：超时后卸载模型。"""
    global _idle_timer_task
    _cancel_idle_timer()

    async def _unload_after_idle():
        await asyncio.sleep(IDLE_TIMEOUT)
        async with model_lock:
            global flux_model
            if flux_model is not None:
                logger.info(f"Idle timeout ({IDLE_TIMEOUT}s) reached, unloading model to free VRAM...")
                flux_model = None
                gc.collect()
                mlx.core.clear_cache()
                logger.info("Model unloaded. VRAM released.")

    _idle_timer_task = asyncio.create_task(_unload_after_idle())


async def _ensure_model():
    """确保模型已加载：若未加载则加载（受 model_lock 保护）。"""
    global flux_model
    if flux_model is not None:
        return
    async with model_lock:
        if flux_model is not None:
            return  # 双重检查：可能在等待锁期间已被其他协程加载
        logger.info(f"Loading FLUX.1-dev from {MODEL_PATH} (pre-quantized q{QUANTIZE})...")
        flux_model = Flux1(model_path=MODEL_PATH, quantize=QUANTIZE, model_config=ModelConfig.dev())
        logger.info("FLUX.1-dev loaded successfully.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Server starting (lazy-load mode, model loads on first request).")
    yield
    _cancel_idle_timer()
    logger.info("Server shutting down.")


app = FastAPI(title="FLUX.1-dev Text-to-Image API", lifespan=lifespan)


class GenerateRequest(BaseModel):
    prompt: str
    width: int = Field(default=1024, ge=64, le=2048)
    height: int = Field(default=1024, ge=64, le=2048)
    steps: int = Field(default=28, ge=1, le=100, alias="num_inference_steps")
    guidance: float = Field(default=3.5, ge=0.0, le=20.0)
    seed: int | None = None
    negative_prompt: str | None = None

    class Config:
        populate_by_name = True


class GenerateResponse(BaseModel):
    success: bool
    image_path: str
    image_base64: str
    seed: int
    prompt: str
    width: int
    height: int
    steps: int
    guidance: float
    generation_time_seconds: float


@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": flux_model is not None}


@app.post("/generate", response_model=GenerateResponse)
async def generate(req: GenerateRequest):
    _cancel_idle_timer()
    await _ensure_model()

    seed = req.seed if req.seed is not None else random.randint(0, 2**32 - 1)
    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    gen_image = flux_model.generate_image(
        seed=seed,
        prompt=req.prompt,
        num_inference_steps=req.steps,
        height=req.height,
        width=req.width,
        guidance=req.guidance,
        negative_prompt=req.negative_prompt,
    )
    elapsed = time.time() - t0

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    filename = f"flux_{timestamp}_seed{seed}.png"
    save_path = os.path.join(OUTPUT_DIR, filename)
    gen_image.save(save_path)

    buf = io.BytesIO()
    gen_image.image.save(buf, format="PNG")
    buf.seek(0)
    img_b64 = base64.b64encode(buf.read()).decode("utf-8")

    logger.info(f"Generated: {save_path}  ({elapsed:.1f}s)")
    _start_idle_timer()

    return GenerateResponse(
        success=True,
        image_path=save_path,
        image_base64=img_b64,
        seed=seed,
        prompt=req.prompt,
        width=req.width,
        height=req.height,
        steps=req.steps,
        guidance=req.guidance,
        generation_time_seconds=round(elapsed, 2),
    )


if __name__ == "__main__":
    import argparse
    import uvicorn

    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9002)
    args = parser.parse_args()
    uvicorn.run(app, host=args.host, port=args.port)
