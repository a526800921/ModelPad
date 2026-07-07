#!/usr/bin/env python3
"""
mlx_lm.server 薄封装。

修复: 请求体中的 model 字段若不在本地 model_map 中，会被 mlx_lm
当作 HuggingFace repo ID 去拉取。这里将未知 model 名称统一回退到
default_model 对应的本地路径。
"""

import sys

if __name__ == "__main__":
    from mlx_lm.server import main, ModelProvider

    # 保存原始 load 方法
    _original_load = ModelProvider.load

    def _patched_load(self, model_path, adapter_path=None, draft_model_path=None):
        """将未知 model 名回退到 default_model，避免远程 HF 查询。"""
        if (
            model_path != "default_model"
            and model_path not in self._model_map
        ):
            model_path = "default_model"
        if (
            draft_model_path
            and draft_model_path != "default_model"
            and draft_model_path not in self._draft_model_map
        ):
            draft_model_path = "default_model"
        return _original_load(self, model_path, adapter_path, draft_model_path)

    ModelProvider.load = _patched_load

    main()
