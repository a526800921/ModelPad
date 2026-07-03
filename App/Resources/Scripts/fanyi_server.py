#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fanyi 专用 MLX LM 服务启动脚本。参数全部由配置传入，无命令行参数时使用默认值。"""

import os
import sys

from mlx_lm.server import main

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

DEFAULT_ARGS = [
    "--model", "/Users/jafish/.cache/modelscope/hub/models/Tencent-Hunyuan/Hy-MT2-1.8B-4bit",
    "--host", "127.0.0.1",
    "--port", "9001",
    "--temp", "0.2",
    "--top-p", "0.8",
    "--top-k", "20",
    "--max-tokens", "2048",
    "--prompt-cache-size", "8",
]

if __name__ == "__main__":
    if len(sys.argv) <= 1:
        sys.argv = [sys.argv[0], *DEFAULT_ARGS]
    raise SystemExit(main())
