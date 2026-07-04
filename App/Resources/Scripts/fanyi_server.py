#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fanyi MLX LM 服务启动脚本。参数全部由 ModelPad 配置传入。"""

import re
import sys
import os

from mlx_lm.server import main

os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw|\.exe)?$", "", sys.argv[0])
    raise SystemExit(main())
