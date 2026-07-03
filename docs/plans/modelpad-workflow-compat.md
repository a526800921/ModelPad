# 计划：ModelPad 外部工作流兼容

## 目标

明确 ModelPad 托管模型与真实外部调用方之间的生命周期边界，避免外部 workflow 误杀由 ModelPad 托管的本地服务型模型。

首个收口对象是 `pdf` 模型与 `/Users/jafish/Documents/work/mineru-pdf-workflow` 的兼容问题：外部 workflow 应完全依赖 ModelPad 托管的 `mineru-api` 服务，不能自行启动或结束该常驻服务。

## 范围

- 明确 ModelPad 托管模型的生命周期所有权：
  - ModelPad 启动的模型只应由 ModelPad 停止、重启，或在 App 完全退出时清理。
  - 外部调用方只应通过端口/API 调用服务，不应按端口直接杀 ModelPad 托管进程。
- 为 `pdf` 模型建立外部 workflow 兼容规则：
  - `mineru-pdf-workflow` 完全依赖 ModelPad 提供的 `9000` 服务。
  - workflow 不再自行启动临时 `mineru-api`。
  - workflow 不再在任务结束后 kill `9000` 服务。
- 验证 `pdf` / `fanyi` 这类本地服务型模型的启动、健康检查、停止和退出清理行为。
- 如需修改外部 workflow 项目，应同步更新对应项目文档；本计划记录 ModelPad 侧托管边界、兼容约束和验收结果。

## 非范围

- 不把 MinerU 或翻译模型的业务脚本内置到 ModelPad。
- 不新增远程访问、鉴权或局域网监听。
- 不要求 ModelPad 识别任意第三方进程所有权；本计划只收口 ModelPad 已托管模型和已知外部调用方的兼容行为。
- 不改变 `modelpad-v1` 阶段 3 已定的外部 HTTP API 配置写入限制。

## 当前阶段

阶段 1 已由外部项目闭环（2026-07-03）。`mineru-pdf-workflow` 已完成 `modelpad-pdf-service-lifecycle` 计划全阶段（0-3），消除了所有服务生命周期副作用。ModelPad 本仓库无需代码改动。

### 外部项目闭环证据

`mineru-pdf-workflow` 仓库 `docs/plans/modelpad-pdf-service-lifecycle.md` 记录以下变更（2026-07-03）：

| 阶段 | 目标 | 状态 |
|---|---|---|
| 阶段 0 | 固化服务生命周期边界 | ✅ |
| 阶段 1 | 移除 `pdf-seg`/`pdf-auto`/`pdf-rerun` 中的服务管理副作用 | ✅ |
| 阶段 2 | 修复 `pdf-auto` 重跑失败 `set -e` 提前退出 | ✅ |
| 阶段 3 | `pdf-merge` 图片同名冲突 SHA-256 检测 | ✅ |

关键行为变化：

- `scripts/pdf-seg`：不再 `kill` 9000 端口进程，不再清理项目 `output/`
- `scripts/pdf-auto`：trap 不再删除项目 `output/`；重跑失败路径免疫 `set -e`
- `scripts/pdf-rerun`：不再清理项目 `output/`
- 三个脚本统一：无 API 服务时明确报错退出（"请先启动 ModelPad PDF 服务"），不走降级路径
- 所有 `mineru` 调用统一使用 `--api-url`

提交记录：`16ce5f9`（阶段 1）、`2786cac`（阶段 2）、`c8a31c2`（阶段 3）。

## 阶段路线图

| 阶段 | 目标 | 进入条件 | 验证方向 | 状态 |
|---|---|---|---|---|
| 阶段 1 | `pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容 | `modelpad-v1` 阶段 6 完成；`pdf` 模型已配置 | ModelPad 托管 `pdf` 后运行外部 workflow，不再导致 9000 服务被误杀 | 已由外部项目闭环 |

## 阶段 1 候选：`pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容

### 背景参考

- 当前 `pdf` 模型配置通过 ModelPad 启动 `mineru-api`，监听 `127.0.0.1:9000`。
- `/Users/jafish/Documents/work/mineru-pdf-workflow/docs/run-summary-2026-07-02.md` 记录了 9000 端口生命周期问题：`pdf-seg` 检测到 9000 端口后复用服务，分段完成后按端口查 PID 并 `kill`，导致 ModelPad 托管的 `pdf` 模型被外部 workflow 结束。
- 根因是所有权边界不清：外部脚本无法区分“自己启动的临时服务”和“ModelPad 托管的常驻服务”。
- 2026-07-03 决策：误杀问题在 `mineru-pdf-workflow` 项目处理，目标是让该 workflow 完全依赖 ModelPad 托管服务。

### Step 0 证据

- `modelpad-v1` 阶段 6 已完成，用户可以通过 `.app` 方式启动 ModelPad。
- `pdf` 模型当前端口为 `9000`，命令内联启动 `mineru-api`。
- `fanyi` 模型当前端口为 `8787`，命令内联启动 `mlx_lm.server`。
- 历史问题（已修复）：`mineru-pdf-workflow/scripts/pdf-seg` 曾在结束时按端口查 PID 并 `kill` 9000 服务，也曾在 `MINERU_API_RESTART=1` 默认值下重启 `mineru-api`。阶段 1 已移除全部服务生命周期副作用。
- 历史问题（已修复）：`pdf-auto` 和 `pdf-rerun` 曾清理项目根目录 `output/`，可能误删 ModelPad 共享运行产物。阶段 1 已移除。
- 当前状态（2026-07-03）：`mineru-pdf-workflow` 三个入口脚本（`pdf-seg`/`pdf-auto`/`pdf-rerun`）均只复用服务、不管理进程、不清理共享目录，无 API 时报错退出。

### 验证方式

阶段 1 完成时至少验证：

- ModelPad 启动 `pdf` 模型后，`9000` 端口可用。
- 运行一次 `mineru-pdf-workflow` 的 `pdf-seg` 或等价最小复现后，若 `pdf` 服务由 ModelPad 托管，`9000` 端口仍保持监听。
- ModelPad UI 中 `pdf` 模型状态不会因为外部 workflow 完成而异常变成 stopped/error。
- ModelPad 停止 `pdf` 模型后，`9000` 端口释放。
- ModelPad 完全退出后，托管的 `pdf` / `fanyi` 进程无残留。
- `mineru-pdf-workflow` 在未检测到 ModelPad 托管 `9000` 服务时，应清晰失败或提示先启动 ModelPad `pdf` 模型，而不是自行启动临时服务。

### 完成条件

- `pdf` 模型与 `mineru-pdf-workflow` 的生命周期冲突有明确修复或可接受的调用约束。
- ModelPad 托管模型不会被已知外部 workflow 误杀。
- `pdf` / `fanyi` 启停、健康检查和退出清理完成验收。
- 相关证据写入本文档，并同步 `docs/PLAN_MAP.md`。

### 阶段 1 完成证据

阶段 1 已由外部项目于 2026-07-03 闭环，并由用户于 2026-07-04 确认完成。

完成证据：

- `/Users/jafish/Documents/work/mineru-pdf-workflow/docs/plans/modelpad-pdf-service-lifecycle.md` 显示阶段 0-3 已完成。
- `scripts/pdf-seg`、`scripts/pdf-auto`、`scripts/pdf-rerun` 均只复用已存在的 ModelPad PDF 服务，不再负责启动、重启、停止服务。
- 三个脚本无 API 服务时明确提示先启动 ModelPad PDF 服务并退出，不再走 MinerU 默认本地启动或降级路径。
- 所有实际解析或重跑的 MinerU 调用均使用 `--api-url "$api_url"`。
- 用户确认外部项目处理已完成；ModelPad 本仓库无需代码改动。

## 测试覆盖率

- 本计划在 ModelPad 仓库内没有新增代码或自动化测试。
- 外部项目 `mineru-pdf-workflow` 已完成脚本级验证和治理检查；用户确认服务生命周期兼容手动集成测试通过。

## 风险和回滚

| 风险 | 影响 | 缓解 | 回滚 |
|---|---|---|---|
| 外部 workflow 仍按端口 kill 常驻服务 | ModelPad UI 状态与实际进程不一致，用户需要重新启动模型 | 在外部 workflow 中移除 kill 常驻服务逻辑，完全依赖 ModelPad 托管服务 | 临时使用 `MINERU_API_RESTART=0` 运行 workflow |
| ModelPad 未启动 `pdf` 时 workflow 无法运行 | 调用方需要先启动托管服务 | 在 workflow 中明确检测 9000 服务并给出启动提示 | 用户先从 ModelPad 启动 `pdf` 模型 |

## 未决问题

| 问题 | 推荐方案 | 是否阻塞当前阶段 | 状态 |
|---|---|---|---|
| 兼容修复应落在 ModelPad 侧、`mineru-pdf-workflow` 侧，还是两边都做 | 修复落在 `mineru-pdf-workflow`，使其完全依赖 ModelPad 托管服务；ModelPad 本仓库暂不改代码 | 否 | 已决 |
