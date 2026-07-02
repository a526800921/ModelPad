# 计划：ModelPad 外部工作流兼容

## 目标

明确 ModelPad 托管模型与真实外部调用方之间的生命周期边界，避免外部 workflow 误杀由 ModelPad 托管的本地服务型模型。

首个收口对象是 `pdf` 模型与 `/Users/jafish/Documents/work/mineru-pdf-workflow` 的兼容问题：外部 workflow 可以复用 ModelPad 托管的 `mineru-api`，但不能在任务结束后结束该常驻服务。

## 范围

- 明确 ModelPad 托管模型的生命周期所有权：
  - ModelPad 启动的模型只应由 ModelPad 停止、重启，或在 App 完全退出时清理。
  - 外部调用方只应通过端口/API 调用服务，不应按端口直接杀 ModelPad 托管进程。
- 为 `pdf` 模型建立外部 workflow 兼容规则：
  - `mineru-pdf-workflow` 复用已存在的 `9000` 服务时，不应在任务结束后 kill。
  - 如果 workflow 自己启动临时 `mineru-api`，才可以在任务结束后清理。
  - 临时 workaround 可使用 `MINERU_API_RESTART=0`，但最终应落实为调用方脚本可重复执行的默认安全行为。
- 验证 `pdf` / `fanyi` 这类本地服务型模型的启动、健康检查、停止和退出清理行为。
- 如需修改外部 workflow 项目，应同步更新对应项目文档；本计划记录 ModelPad 侧托管边界、兼容约束和验收结果。

## 非范围

- 不把 MinerU 或翻译模型的业务脚本内置到 ModelPad。
- 不新增远程访问、鉴权或局域网监听。
- 不要求 ModelPad 识别任意第三方进程所有权；本计划只收口 ModelPad 已托管模型和已知外部调用方的兼容行为。
- 不改变 `modelpad-v1` 阶段 3 已定的外部 HTTP API 配置写入限制。

## 当前阶段

当前阶段：阶段 1 候选（`pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容）。

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | `pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容 | `modelpad-v1` 阶段 6 完成；`pdf` 模型已配置 | ModelPad 托管 `pdf` 后运行外部 workflow，不再导致 9000 服务被误杀 | 候选 |

## 阶段 1 候选：`pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容

### 背景参考

- 当前 `pdf` 模型配置通过 ModelPad 启动 `mineru-api`，监听 `127.0.0.1:9000`。
- `/Users/jafish/Documents/work/mineru-pdf-workflow/docs/run-summary-2026-07-02.md` 记录了 9000 端口生命周期问题：`pdf-seg` 检测到 9000 端口后复用服务，分段完成后按端口查 PID 并 `kill`，导致 ModelPad 托管的 `pdf` 模型被外部 workflow 结束。
- 根因是所有权边界不清：外部脚本无法区分“自己启动的临时服务”和“ModelPad 托管的常驻服务”。

### Step 0 证据

- `modelpad-v1` 阶段 6 已完成，用户可以通过 `.app` 方式启动 ModelPad。
- `pdf` 模型当前端口为 `9000`，命令内联启动 `mineru-api`。
- `fanyi` 模型当前端口为 `8787`，命令内联启动 `mlx_lm.server`。
- 已读到运行总结 `/Users/jafish/Documents/work/mineru-pdf-workflow/docs/run-summary-2026-07-02.md`，其中记录 `pdf-seg` 在复用 9000 端口后会结束该服务。
- 代码排查确认 `mineru-pdf-workflow/scripts/pdf-seg` 默认 `MINERU_API_RESTART=1`，结束时按 `${MINERU_API_BASE_PORT:-9000}` 查找监听进程并 kill。

### 验证方式

阶段 1 完成时至少验证：

- ModelPad 启动 `pdf` 模型后，`9000` 端口可用。
- 运行一次 `mineru-pdf-workflow` 的 `pdf-seg` 或等价最小复现后，若 `pdf` 服务由 ModelPad 托管，`9000` 端口仍保持监听。
- ModelPad UI 中 `pdf` 模型状态不会因为外部 workflow 完成而异常变成 stopped/error。
- ModelPad 停止 `pdf` 模型后，`9000` 端口释放。
- ModelPad 完全退出后，托管的 `pdf` / `fanyi` 进程无残留。
- 如外部 workflow 自己启动临时 `mineru-api`，任务结束后仍能清理该临时进程。

### 完成条件

- `pdf` 模型与 `mineru-pdf-workflow` 的生命周期冲突有明确修复或可接受的调用约束。
- ModelPad 托管模型不会被已知外部 workflow 误杀。
- `pdf` / `fanyi` 启停、健康检查和退出清理完成验收。
- 相关证据写入本文档，并同步 `docs/PLAN_MAP.md`。

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 外部 workflow 仍按端口 kill 常驻服务 | ModelPad UI 状态与实际进程不一致，用户需要重新启动模型 | 在外部 workflow 中区分外部服务和临时服务；默认不 kill 已存在服务 | 临时使用 `MINERU_API_RESTART=0` 运行 workflow |
| 临时服务无法被清理 | 9000 或相邻端口残留进程，影响后续运行 | 只清理 workflow 自己启动的 PID | 手动停止临时进程或重启 workflow 环境 |

## 未决问题

| 问题 | 推荐方案 | 是否阻塞当前阶段 | 状态 |
|---|---|---|---|
| 兼容修复应落在 ModelPad 侧、`mineru-pdf-workflow` 侧，还是两边都做 | 优先修调用方 workflow 的所有权判断；ModelPad 侧只补必要的状态刷新/异常检测 | 是 | 待确认 |
