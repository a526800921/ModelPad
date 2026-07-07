#!/usr/bin/env python3
"""
Qwen3.6-35B-A3B GGUF (unsloth UD) 推理服务 — llama-server 薄封装。

llama-server 自身提供 OpenAI 兼容的 /v1/chat/completions 端点。
"""

import os
import runpy

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

if __name__ == "__main__":
    runpy.run_path(
        os.path.join(_SCRIPT_DIR, "llama_server.py"),
        run_name="__main__",
    )
