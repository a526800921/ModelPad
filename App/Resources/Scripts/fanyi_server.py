#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fanyi 专用 MLX LM 服务启动脚本。"""

import os
import sys

from mlx_lm.server import main

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

SERVER_ARGS = [
    "--model",
    "/Users/jafish/.cache/modelscope/hub/models/Tencent-Hunyuan/Hy-MT2-1.8B-4bit",
    "--host",
    "127.0.0.1",
    "--port",
    "8787",
    "--temp",
    "0.2",
    "--top-p",
    "0.8",
    "--top-k",
    "20",
    "--max-tokens",
    "2048",
    "--prompt-cache-size",
    "8",
    "--log-level",
    "WARNING",
]


if __name__ == "__main__":
    sys.argv = [sys.argv[0], *SERVER_ARGS]
    raise SystemExit(main())
