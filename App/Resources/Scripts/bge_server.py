#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BGE Embedding 服务 — 基于 sentence-transformers 加载 BAAI/bge 系列模型，
提供 OpenAI 兼容的 /v1/embeddings 接口，以及文本相似度与检索测试接口。

端点：
  GET  /health            — 健康检查（含模型信息）
  POST /v1/embeddings     — 文本向量化（OpenAI 兼容）
  POST /v1/similarity     — 两段文本余弦相似度
  POST /v1/retrieve       — 查询 + 文档列表 → Top-K 检索
"""

import os
import sys
import time
import json
import argparse
import logging
from typing import List, Optional

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import uvicorn
from contextlib import asynccontextmanager

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pydantic 模型
# ---------------------------------------------------------------------------

class EmbeddingRequest(BaseModel):
    input: str | List[str] = Field(..., description="要向量化的文本（单条或多条）")
    model: str = Field(default="bge-small-zh-v1.5", description="模型名称（仅作标记）")

class EmbeddingData(BaseModel):
    object: str = "embedding"
    index: int
    embedding: List[float]

class EmbeddingUsage(BaseModel):
    prompt_tokens: int
    total_tokens: int

class EmbeddingResponse(BaseModel):
    object: str = "list"
    data: List[EmbeddingData]
    model: str
    usage: EmbeddingUsage

class SimilarityRequest(BaseModel):
    text1: str = Field(..., description="文本 1")
    text2: str = Field(..., description="文本 2")

class SimilarityResponse(BaseModel):
    text1: str
    text2: str
    cosine_similarity: float

class RetrieveRequest(BaseModel):
    query: str = Field(..., description="查询文本")
    documents: List[str] = Field(..., description="待检索文档列表")
    top_k: int = Field(default=5, ge=1, le=100, description="返回的 Top-K 数量")

class RetrieveItem(BaseModel):
    index: int
    document: str
    score: float

class RetrieveResponse(BaseModel):
    query: str
    results: List[RetrieveItem]

# ---------------------------------------------------------------------------
# 模型加载
# ---------------------------------------------------------------------------

_model = None
_model_name: str = ""
_embedding_dim: int = 0

def load_model(model_path: str):
    """延迟加载模型（首次请求时触发）。"""
    global _model, _model_name, _embedding_dim

    if _model is not None:
        return

    from sentence_transformers import SentenceTransformer

    logger.info(f"Loading BGE model from: {model_path}")
    t0 = time.time()
    _model = SentenceTransformer(model_path, trust_remote_code=True)
    _model_name = os.path.basename(model_path.rstrip("/"))
    _embedding_dim = _model.get_embedding_dimension()
    logger.info(
        f"Model loaded in {time.time() - t0:.1f}s — "
        f"name={_model_name}, dim={_embedding_dim}"
    )

def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """两个 1-D 向量之间的余弦相似度。"""
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-10))

# ---------------------------------------------------------------------------
# FastAPI App
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(application: FastAPI):
    model_path = os.getenv("BGE_MODEL_PATH", "")
    if model_path:
        load_model(model_path)
    yield


app = FastAPI(
    title="BGE Embedding Server",
    version="1.0.0",
    description="BAAI/bge-small-zh-v1.5 Embedding + Retrieval Service",
    lifespan=lifespan,
)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": _model_name or "(not loaded)",
        "embedding_dim": _embedding_dim,
    }


# ---------------------------------------------------------------------------
# /v1/embeddings — OpenAI 兼容
# ---------------------------------------------------------------------------

@app.post("/v1/embeddings", response_model=EmbeddingResponse)
def embeddings(req: EmbeddingRequest):
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    texts = [req.input] if isinstance(req.input, str) else req.input
    if not texts:
        raise HTTPException(status_code=400, detail="input is empty")

    t0 = time.time()
    vectors = _model.encode(texts, normalize_embeddings=True, show_progress_bar=False)
    # ensure 2-D
    if vectors.ndim == 1:
        vectors = np.expand_dims(vectors, axis=0)

    elapsed_ms = round((time.time() - t0) * 1000)

    data = [
        EmbeddingData(index=i, embedding=vec.tolist())
        for i, vec in enumerate(vectors)
    ]
    # 粗糙 token 估算（中英文混合，按字符数折半）
    total_chars = sum(len(t) for t in texts)
    usage = EmbeddingUsage(prompt_tokens=total_chars, total_tokens=total_chars)

    logger.info(f"/v1/embeddings batch={len(texts)} dim={vectors.shape[1]} time={elapsed_ms}ms")
    return EmbeddingResponse(
        data=data,
        model=_model_name,
        usage=usage,
    )


# ---------------------------------------------------------------------------
# /v1/similarity — 两段文本相似度
# ---------------------------------------------------------------------------

@app.post("/v1/similarity", response_model=SimilarityResponse)
def similarity(req: SimilarityRequest):
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    vecs = _model.encode(
        [req.text1, req.text2],
        normalize_embeddings=True,
        show_progress_bar=False,
    )
    sim = cosine_similarity(vecs[0], vecs[1])
    return SimilarityResponse(text1=req.text1, text2=req.text2, cosine_similarity=sim)


# ---------------------------------------------------------------------------
# /v1/retrieve — 查询 + 文档列表 → Top-K 检索
# ---------------------------------------------------------------------------

@app.post("/v1/retrieve", response_model=RetrieveResponse)
def retrieve(req: RetrieveRequest):
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    n = len(req.documents)
    if n == 0:
        return RetrieveResponse(query=req.query, results=[])

    k = min(req.top_k, n)
    t0 = time.time()

    # query + documents 一批编码
    all_texts = [req.query] + req.documents
    all_vecs = _model.encode(all_texts, normalize_embeddings=True, show_progress_bar=False)

    query_vec = all_vecs[0]
    doc_vecs = all_vecs[1:]

    scores = np.dot(doc_vecs, query_vec)  # 已归一化，点积 = 余弦相似度

    top_indices = np.argsort(-scores, kind="stable")[:k].tolist()
    results = [
        RetrieveItem(
            index=i,
            document=req.documents[i],
            score=round(float(scores[i]), 6),
        )
        for i in top_indices
    ]

    logger.info(
        f"/v1/retrieve docs={n} top_k={k} time={round((time.time() - t0) * 1000)}ms"
    )
    return RetrieveResponse(query=req.query, results=results)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="BGE Embedding Server")
    parser.add_argument("--model", required=True, help="模型路径")
    parser.add_argument("--host", default="127.0.0.1", help="绑定地址，默认 127.0.0.1")
    parser.add_argument("--port", type=int, required=True, help="监听端口")
    args, unknown = parser.parse_known_args()

    os.environ["BGE_MODEL_PATH"] = args.model

    logger.info(f"BGE Embedding Server starting on {args.host}:{args.port}")
    logger.info(f"Model path: {args.model}")

    config = uvicorn.Config(
        app,
        host=args.host,
        port=args.port,
        reload=False,
        access_log=True,
    )
    server = uvicorn.Server(config)
    server.run()


if __name__ == "__main__":
    main()
