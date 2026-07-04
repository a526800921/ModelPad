#!/usr/bin/env python3
"""
llama.cpp 推理服务包装器 — 管理 llama-server 子进程生命周期。

用于 GGUF 格式模型，支持原生 MoE、Flash Attention、MTP 投机解码等特性。
llama-server 自身提供 OpenAI 兼容的 /v1/chat/completions 端点。
"""

import os
import sys
import signal
import time
import logging
import subprocess
import argparse

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def find_llama_server() -> str:
    """查找 llama-server 路径。"""
    paths = [
        "/opt/homebrew/bin/llama-server",
        "/usr/local/bin/llama-server",
        os.path.expanduser("~/.local/bin/llama-server"),
    ]
    for p in paths:
        if os.path.isfile(p):
            return p
    # fallback: 从 PATH 查找
    result = subprocess.run(
        ["which", "llama-server"], capture_output=True, text=True
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    logger.error("llama-server not found. Install: brew install llama.cpp")
    sys.exit(1)


def build_args(args) -> list[str]:
    """根据 CLI 参数构建 llama-server 命令行参数。"""
    cmd = [
        find_llama_server(),
        "-m", args.model,
        "--host", args.host,
        "--port", str(args.port),
    ]
    if args.alias:
        cmd += ["--alias", args.alias]
    if args.ngl > 0:
        cmd += ["-ngl", str(args.ngl)]
    if args.ncmoe > 0:
        cmd += ["-ncmoe", str(args.ncmoe)]
    if args.ctx_size > 0:
        cmd += ["-c", str(args.ctx_size)]
    if args.flash_attn:
        cmd += ["-fa", args.flash_attn]
    if args.spec_type:
        cmd += ["--spec-type", args.spec_type]
    if args.spec_draft_n_max > 0:
        cmd += ["--spec-draft-n-max", str(args.spec_draft_n_max)]
    if args.reasoning:
        cmd += ["--reasoning", args.reasoning]
    if args.batch_size > 0:
        cmd += ["-b", str(args.batch_size)]
    if args.ubatch_size > 0:
        cmd += ["-ub", str(args.ubatch_size)]
    if args.threads > 0:
        cmd += ["-t", str(args.threads)]
    if args.cache_type_k:
        cmd += ["-ctk", args.cache_type_k]
    if args.cache_type_v:
        cmd += ["-ctv", args.cache_type_v]
    if args.mlock:
        cmd += ["--mlock"]
    return cmd


def main():
    parser = argparse.ArgumentParser(
        description="llama.cpp Server Wrapper (GGUF models)"
    )
    parser.add_argument(
        "--model", required=True,
        help="GGUF 模型文件路径",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9005)
    parser.add_argument("--alias", default=None, help="模型别名（API 用）")

    # 硬件 / 性能
    parser.add_argument("--ngl", type=int, default=99,
                        help="GPU 层数（默认 99，尽可能多）")
    parser.add_argument("--ncmoe", type=int, default=0,
                        help="MoE 并发专家数")
    parser.add_argument("--ctx-size", "-c", type=int, default=131072,
                        help="上下文窗口大小（默认 131072）")
    parser.add_argument("--flash-attn", "-fa", default="auto",
                        choices=["on", "off", "auto"])
    parser.add_argument("--threads", "-t", type=int, default=0,
                        help="CPU 线程数（0 = 自动）")
    parser.add_argument("--batch-size", "-b", type=int, default=0)
    parser.add_argument("--ubatch-size", "-ub", type=int, default=0)

    # KV cache 量化
    parser.add_argument("--cache-type-k", "-ctk", default=None,
                        choices=["f32", "f16", "bf16", "q8_0", "q4_0", "q4_1", "iq4_nl", "q5_0", "q5_1"])
    parser.add_argument("--cache-type-v", "-ctv", default=None,
                        choices=["f32", "f16", "bf16", "q8_0", "q4_0", "q4_1", "iq4_nl", "q5_0", "q5_1"])

    # 内存锁定
    parser.add_argument("--mlock", action="store_true",
                        help="锁定内存防止 swap")

    # 投机解码
    parser.add_argument("--spec-type", default=None,
                        help="投机解码类型（如 draft-mtp）")
    parser.add_argument("--spec-draft-n-max", type=int, default=0,
                        help="最大草稿 token 数")

    # 思考模式
    parser.add_argument("--reasoning", default=None,
                        choices=["on", "off", "auto"],
                        help="思考/推理模式（默认 auto）")

    args = parser.parse_args()

    cmd = build_args(args)
    logger.info(f"Starting llama-server: {' '.join(cmd)}")

    proc = subprocess.Popen(
        cmd,
        stdout=sys.stdout,
        stderr=sys.stderr,
        # 将 SIGINT/SIGTERM 传给子进程
    )

    def on_signal(signum, frame):
        logger.info(f"Received signal {signum}, stopping llama-server ...")
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            logger.warning("llama-server didn't exit, sending SIGKILL")
            proc.kill()
            proc.wait()
        sys.exit(0)

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    # 等待子进程退出
    rc = proc.wait()
    logger.info(f"llama-server exited with code {rc}")
    sys.exit(rc)


if __name__ == "__main__":
    main()
