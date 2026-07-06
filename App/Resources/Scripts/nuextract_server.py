#!/usr/bin/env python3
"""
NuExtract 专用提取服务 — 包装 llama-server，提供简化 /extract 端点。

自动处理 NuExtract prompt 模板、JSON schema 约束，调用方只需传 text + template。
"""

import os
import sys
import json
import signal
import time
import logging
import argparse
import asyncio
import subprocess
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ---------- 日志 ----------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("nuextract")

# ---------- 全局 ----------
llama_proc: Optional[subprocess.Popen] = None
LLAMA_PORT: int = 0
MODEL_READY = False

# ---------- FastAPI ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    global llama_proc, LLAMA_PORT, MODEL_READY
    args = app.state.args

    LLAMA_PORT = args.llama_port

    # 启动 llama-server
    cmd = build_llama_cmd(args)
    logger.info(f"Starting llama-server: {' '.join(cmd)}")
    llama_proc = subprocess.Popen(cmd, stdout=sys.stderr, stderr=sys.stderr)

    # 等待 llama-server 就绪
    import urllib.request
    for i in range(60):
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{LLAMA_PORT}/health")
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = json.loads(resp.read())
                if data.get("status") == "ok":
                    MODEL_READY = True
                    logger.info("llama-server is ready")
                    break
        except Exception:
            pass
        time.sleep(1)

    if not MODEL_READY:
        logger.error("llama-server failed to start within 60s")
        llama_proc.terminate()
        sys.exit(1)

    yield

    logger.info("Shutting down llama-server ...")
    if llama_proc:
        llama_proc.terminate()
        try:
            llama_proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            llama_proc.kill()
            llama_proc.wait()
    logger.info("Server stopped")


app = FastAPI(title="NuExtract API", lifespan=lifespan)


# ---------- 请求/响应 ----------
class ExtractRequest(BaseModel):
    text: str = Field(..., description="待提取的文本")
    template: dict = Field(..., description="提取模板，值为空字符串或空数组，如 {'name': '', 'tags': []}")


class ExtractResponse(BaseModel):
    ok: bool = True
    result: dict = Field(default_factory=dict)


class ErrorResponse(BaseModel):
    ok: bool = False
    error: str


# ---------- llama-server 命令行 ----------
def find_llama_server() -> str:
    paths = [
        "/opt/homebrew/bin/llama-server",
        "/usr/local/bin/llama-server",
    ]
    for p in paths:
        if os.path.isfile(p):
            return p
    result = subprocess.run(["which", "llama-server"], capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    logger.error("llama-server not found")
    sys.exit(1)


def build_llama_cmd(args) -> list[str]:
    return [
        find_llama_server(),
        "-m", args.model,
        "--host", "127.0.0.1",
        "--port", str(args.llama_port),
        "--alias", args.alias,
        "-ngl", str(args.ngl),
        "-c", str(args.ctx_size),
        "--mlock",
        "--log-disable",  # llama-server 自己的日志全禁，避免干扰
    ]


# ---------- NuExtract prompt ----------
NUEXTRACT_TEMPLATE = """<|input|>
### Template:
{template_json}

### Text:
{text}

<|output|>
"""


def template_to_json_schema(template: dict) -> dict:
    """将提取模板转为 JSON Schema，用于 llama-server 约束输出。"""

    def _convert(value):
        if isinstance(value, dict):
            props = {k: _convert(v) for k, v in value.items()}
            required = list(value.keys())
            return {
                "type": "object",
                "properties": props,
                "required": required,
                "additionalProperties": False,
            }
        elif isinstance(value, list):
            return {"type": "array", "items": {"type": "string"}}
        elif isinstance(value, str):
            return {"type": "string"}
        else:
            return {"type": "string"}

    return _convert(template)


# ---------- 路由 ----------
@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": MODEL_READY}


@app.post("/extract")
async def extract(req: ExtractRequest):
    if not MODEL_READY:
        raise HTTPException(503, "model not ready")

    # 格式化 NuExtract prompt
    template_str = json.dumps(req.template, indent=4, ensure_ascii=False)
    prompt = NUEXTRACT_TEMPLATE.format(
        template_json=template_str,
        text=req.text,
    )

    # 生成 JSON schema 约束
    json_schema = template_to_json_schema(req.template)

    # 调用 llama-server
    import urllib.request
    import urllib.error

    llama_url = f"http://127.0.0.1:{LLAMA_PORT}/v1/chat/completions"
    payload = {
        "messages": [
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 1024,
        "temperature": 0.0,
        "response_format": {
            "type": "json_schema",
            "json_schema": {
                "name": "extraction",
                "schema": json_schema,
            },
        },
    }

    tic = time.time()
    try:
        data = json.dumps(payload).encode("utf-8")
        req_obj = urllib.request.Request(
            llama_url,
            data=data,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req_obj, timeout=120) as resp:
            result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else str(e)
        raise HTTPException(502, f"llama-server error: {body}")
    except Exception as e:
        raise HTTPException(502, f"llama-server unreachable: {e}")

    elapsed = time.time() - tic

    # 解析结果
    choices = result.get("choices", [])
    if not choices:
        raise HTTPException(500, "empty response from model")

    content = choices[0]["message"].get("content", "")
    try:
        extracted = json.loads(content)
    except json.JSONDecodeError:
        # 如果 JSON 解析失败，返回原始内容
        raise HTTPException(500, f"model returned invalid JSON: {content[:200]}")

    usage = result.get("usage", {})
    logger.info(
        f"Extraction done in {elapsed:.1f}s, "
        f"prompt={usage.get('prompt_tokens', '?')}t, "
        f"completion={usage.get('completion_tokens', '?')}t"
    )

    return ExtractResponse(result=extracted)


# ---------- 主入口 ----------
def main():
    parser = argparse.ArgumentParser(description="NuExtract Extraction Server")
    parser.add_argument(
        "--model",
        default=os.path.expanduser(
            "~/.cache/modelscope/hub/models/DevQuasar/"
            "numind___NuExtract-tiny-v1___5-GGUF/"
            "numind.NuExtract-tiny-v1.5.Q4_K_M.gguf"
        ),
    )
    parser.add_argument("--host", default="127.0.0.1", help="外部 API 监听地址")
    parser.add_argument("--port", type=int, default=9007, help="外部 API 端口")
    parser.add_argument("--llama-port", type=int, default=19007,
                        help="llama-server 内部端口（不对外暴露）")
    parser.add_argument("--alias", default="nuextract")
    parser.add_argument("--ngl", type=int, default=99, help="GPU 层数")
    parser.add_argument("--ctx-size", "-c", type=int, default=8192,
                        help="上下文窗口大小")

    args = parser.parse_args()
    app.state.args = args

    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
