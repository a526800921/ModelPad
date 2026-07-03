#!/usr/bin/env python3
"""
PDF (MinerU) 服务 wrapper — 增加 VLM 模型空闲超时自动卸载。

MinerU 官方 fast_api 没有 idle unload 机制，VLM 模型首次加载后常驻内存。
本 wrapper 在每次请求完成后启动空闲定时器，超时后调用 shutdown_cached_models()
释放 VLM 显存/内存，下次请求时模型按需重载。
"""

import os
import sys
import time
import asyncio
import logging
from pathlib import Path

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

IDLE_TIMEOUT = int(os.getenv("MINERU_IDLE_TIMEOUT_SECONDS", "300"))  # 默认 5 分钟


async def idle_unload_loop(app, timeout: int):
    """后台循环：空闲超时后卸载 VLM 模型。"""
    last_active = time.time()

    # 记录请求时间
    from starlette.middleware.base import BaseHTTPMiddleware

    class ActivityTracker(BaseHTTPMiddleware):
        async def dispatch(self, request, call_next):
            nonlocal last_active
            # 跳过健康检查
            if request.url.path != "/health":
                last_active = time.time()
            return await call_next(request)

    app.add_middleware(ActivityTracker)

    while True:
        await asyncio.sleep(30)  # 每 30s 检查一次
        idle = time.time() - last_active
        if idle >= timeout:
            try:
                from mineru.backend.vlm.vlm_analyze import shutdown_cached_models
                shutdown_cached_models()
                logger.info(f"Idle {idle:.0f}s >= {timeout}s, VLM model unloaded.")
            except Exception as e:
                logger.warning(f"VLM unload failed: {e}")


def main():
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--idle-timeout", type=int, default=IDLE_TIMEOUT,
                        help="VLM 空闲超时秒数，默认 300 (5 分钟)")
    parser.add_argument("--enable-vlm-preload", type=bool, default=False)
    args, unknown = parser.parse_known_args()

    # 把已知参数注入环境变量，其余透传给 mineru
    os.environ["MINERU_API_ENABLE_VLM_PRELOAD"] = "1" if args.enable_vlm_preload else "0"

    # 动态 import mineru fast_api app，注入 idle unload
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import importlib
    import mineru.cli.fast_api as mineru_app_module

    app = mineru_app_module.app

    # 启动 idle unload 后台任务
    @app.on_event("startup")
    async def startup_idle_unload():
        asyncio.create_task(idle_unload_loop(app, args.idle_timeout))

    import uvicorn
    logger.info(f"Starting PDF server with idle unload ({args.idle_timeout}s timeout)")
    config = uvicorn.Config(app, host=args.host, port=args.port, reload=False,
                            access_log=not os.getenv("MINERU_API_DISABLE_ACCESS_LOG"))
    server = uvicorn.Server(config)
    server.run()


if __name__ == "__main__":
    main()
