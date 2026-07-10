#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
qwen3_vl_server.py — MLX VLM Server Wrapper

功能：
  启动 mlx_vlm.server，并强制使用 --model 指定的模型路径，
  忽略外部 API 请求中的 model 字段，防止因 model 名不匹配
  导致服务尝试从 HuggingFace Hub 下载模型。
"""
import re
import sys
import os

# ── Step 1: 提前提取 --model 路径（在模块导入之前） ──────────────────────
REAL_MODEL_PATH = None
for i, arg in enumerate(sys.argv):
    if arg == "--model" and i + 1 < len(sys.argv):
        REAL_MODEL_PATH = sys.argv[i + 1]
        break

# ── Step 2: 导入 mlx_vlm.server ─────────────────────────────────────
# 这会触发 app.py 模块级初始化，包括创建 FastAPI app、注册路由等。
# cli.main() 中的 lifespan 回调会在 uvicorn 启动后消费 MLX_VLM_PRELOAD_MODEL
# 环境变量进行预加载，但我们在此之前先修补路由层的模型名解析逻辑。
from mlx_vlm.server import main  # noqa: E402
import mlx_vlm.server.openai as openai_mod  # noqa: E402

# ── Step 3: 修补 get_cached_model，强制使用固定模型路径 ─────────────────
if REAL_MODEL_PATH:
    _original_get_cached = openai_mod.get_cached_model

    def _force_model_get_cached(model_name, *args, **kwargs):
        """
        忽略请求中的 model 字段，始终使用 --model 指定的路径。

        model_kind 为 'image_edit' / 'image_generation' / 'audio_*'
        时不强制（这些不是 VLM 请求），保持原行为。
        """
        model_kind = kwargs.get("model_kind", "auto")
        if model_kind not in ("image_edit", "image_generation", "audio_tts", "audio_stt"):
            print(f"[qwen3_vl_server] force model: '{model_name}' -> '{REAL_MODEL_PATH}'")
            return _original_get_cached(REAL_MODEL_PATH, *args, **kwargs)
        return _original_get_cached(model_name, *args, **kwargs)

    openai_mod.get_cached_model = _force_model_get_cached

# ── Step 4: 启动服务器 ──────────────────────────────────────────────
if __name__ == "__main__":
    sys.argv[0] = re.sub(r'(-script\.pyw|\.exe)?$', '', sys.argv[0])
    sys.exit(main())
