#!/usr/bin/env python3
"""
SD 3.5 Medium 文生图 FastAPI 服务
- 后端: PyTorch + diffusers + MPS
- 模型路径: ModelScope 缓存目录
- 空闲超时自动卸载 GPU 显存
"""

import os
import io
import gc
import base64
import random
import time
import logging
import asyncio
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import torch
from diffusers import StableDiffusion3Pipeline
from modelscope import snapshot_download

# ---------- 配置 ----------
MODEL_ID = "AI-ModelScope/stable-diffusion-3.5-medium"
MODEL_LOCAL_PATH = snapshot_download(MODEL_ID)  # 下载/读取 ModelScope 缓存
OUTPUT_DIR = os.path.expanduser("~/Documents/models/output/")
IDLE_TIMEOUT = 5  # 空闲超时秒数，超时后卸载模型释放显存

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

pipe: StableDiffusion3Pipeline | None = None
model_lock = asyncio.Lock()
_idle_timer_task: asyncio.Task | None = None


def _cancel_idle_timer():
    global _idle_timer_task
    if _idle_timer_task is not None and not _idle_timer_task.done():
        _idle_timer_task.cancel()
        _idle_timer_task = None


def _start_idle_timer():
    global _idle_timer_task
    _cancel_idle_timer()

    async def _unload_after_idle():
        await asyncio.sleep(IDLE_TIMEOUT)
        async with model_lock:
            global pipe
            if pipe is not None:
                logger.info(f"Idle timeout ({IDLE_TIMEOUT}s) reached, unloading model...")
                pipe = None
                gc.collect()
                if torch.backends.mps.is_available():
                    torch.mps.empty_cache()
                logger.info("Model unloaded.")

    _idle_timer_task = asyncio.create_task(_unload_after_idle())


async def _ensure_model():
    global pipe
    if pipe is not None:
        return
    async with model_lock:
        if pipe is not None:
            return
        logger.info(f"Loading SD 3.5 Medium from {MODEL_LOCAL_PATH}...")
        pipe = StableDiffusion3Pipeline.from_pretrained(
            MODEL_LOCAL_PATH,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True,
        )
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        pipe = pipe.to(device)
        logger.info(f"SD 3.5 Medium loaded on {device}.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Server starting (lazy-load mode).")
    yield
    _cancel_idle_timer()
    logger.info("Server shutting down.")


app = FastAPI(title="SD 3.5 Medium Text-to-Image API", lifespan=lifespan)


class GenerateRequest(BaseModel):
    prompt: str
    width: int = Field(default=1024, ge=64, le=2048)
    height: int = Field(default=1024, ge=64, le=2048)
    steps: int = Field(default=28, ge=1, le=100, alias="num_inference_steps")
    guidance: float = Field(default=4.5, ge=0.0, le=20.0)
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
    return {"status": "ok", "model_loaded": pipe is not None}


@app.post("/generate", response_model=GenerateResponse)
async def generate(req: GenerateRequest):
    _cancel_idle_timer()
    await _ensure_model()

    seed = req.seed if req.seed is not None else random.randint(0, 2**32 - 1)
    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    generator = torch.Generator(device=pipe.device).manual_seed(seed)
    gen_image = pipe(
        prompt=req.prompt,
        negative_prompt=req.negative_prompt,
        num_inference_steps=req.steps,
        height=req.height,
        width=req.width,
        guidance_scale=req.guidance,
        generator=generator,
    ).images[0]
    elapsed = time.time() - t0

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    filename = f"sd3_{timestamp}_seed{seed}.png"
    save_path = os.path.join(OUTPUT_DIR, filename)
    gen_image.save(save_path)

    buf = io.BytesIO()
    gen_image.save(buf, format="PNG")
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
    parser.add_argument("--port", type=int, default=9003)
    args = parser.parse_args()
    uvicorn.run(app, host=args.host, port=args.port)
