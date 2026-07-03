# PLAN_MAP

## 治理范围

本文件只跟踪跨阶段、影响公共契约、依赖真实反馈，或会与其他计划发生关系的计划。普通一次性任务不要加入这里。

## 文档权责

- `docs/PLAN_MAP.md` 是状态、依赖、替代/合并/废弃关系、推荐顺序、阻塞项和证据链接的事实源。
- `docs/plans/*.md` 是专项计划的实施细节事实源，记录字段方案、Schema、枚举、Step 0 证据、验证方式和完成条件。
- 总路线图、优先级计划和索引只记录顺序、状态摘要和专项计划链接，不复制字段级方案、枚举、Step 0 细节或完成定义。
- 当专项计划变化时，必须同步所有引用该计划的路线图、优先级计划或索引。
- 如果同一事实在多个文档中重复，保留一个事实源，其他文档改为链接引用。
- 启用治理后，已有草案、历史设计、归档计划和临时分析文档默认只作为背景材料，不再作为规范事实源；后续新规范默认进入 `docs/plans/*.md`、ADR、migration、正式 spec 或 `docs/PLAN_MAP.md`。

## 计划索引

| 计划 | 状态 | 当前阶段 | 依赖 | 证据 |
|---|---|---|---|---|
| [ModelPad v1 实施计划](plans/modelpad-v1.md) | 已完成 | v1 全部阶段已完成 | - | [阶段 1-6 证据](plans/modelpad-v1.md#阶段-6-完成证据) |
| [ModelPad LogBuffer 性能优化](plans/modelpad-logbuffer-performance.md) | 待实施 | 阶段 1：环形缓冲替换 | modelpad-v1 | [Step 0 证据](plans/modelpad-logbuffer-performance.md#step-0-证据) |
| [ModelPad 外部工作流兼容](plans/modelpad-workflow-compat.md) | 候选 | 阶段 1：`pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容（待外部项目处理） | modelpad-v1 | [Step 0 证据](plans/modelpad-workflow-compat.md#step-0-证据) |
| [ModelPad PDF 模型优化方案](plans/modelpad-pdf-model-optimization.md) | 候选 | 阶段 1：配置层稳定性优化 | modelpad-v1, modelpad-workflow-compat | [Step 0 证据](plans/modelpad-pdf-model-optimization.md#step-0-证据) |
| [ModelPad 菜单栏常驻和启动配置增强](plans/modelpad-menu-bar-agent.md) | 待实施 | 阶段 3：MLX 引擎选项和 API 启停后的 UI 状态同步 | modelpad-v1 | [阶段 2 完成证据](plans/modelpad-menu-bar-agent.md#阶段-2-完成证据) |

允许状态：`候选`、`设计中`、`待实施`、`实施中`、`已完成`、`已替代`、`已合并`、`已废弃`。

## 推荐顺序

1. `modelpad-v1` ✅（全部阶段已完成）
2. `modelpad-logbuffer-performance` 阶段 1 待实施：优先修复日志热路径 `LogBuffer.append` 的锁内数组移位问题，将日志缓冲改为环形缓冲。
3. `modelpad-workflow-compat` 阶段 1：等待用户在 `mineru-pdf-workflow` 项目处理，使其完全依赖 ModelPad 托管服务。
4. `modelpad-pdf-model-optimization` 阶段 1 候选：在不改代码的前提下收敛 `pdf` 模型服务端环境变量、输出目录、日志和任务保留策略。
5. `modelpad-menu-bar-agent` 阶段 3 待实施：增加 MLX 引擎选项，并修复外部 API 启停模型后主面板状态不实时更新的问题。

## 依赖关系

| 计划 | 依赖 | 原因 |
|---|---|---|
| modelpad-v1 | - | - |
| modelpad-logbuffer-performance | modelpad-v1 | 依赖阶段 2 已建立的 `LogBuffer`、进程输出捕获和日志测试基础 |
| modelpad-workflow-compat | modelpad-v1 | 依赖 `.app` 启动入口、模型托管、健康检查和退出清理能力已完成 |
| modelpad-pdf-model-optimization | modelpad-v1, modelpad-workflow-compat | 依赖 ModelPad 模型托管能力；验证需避免与外部 workflow 生命周期冲突混淆 |
| modelpad-menu-bar-agent | modelpad-v1 | 依赖 `.app` 启动入口、菜单栏图标、退出流程和打包流程已完成 |

## 替代、合并和废弃

| 计划 | 关系 | 目标 | 原因 |
|---|---|---|---|
| - | - | - | - |

## 当前阻塞项

| 问题 | 推荐方案 | 影响范围 | 是否阻塞当前阶段 | 状态 |
|---|---|---|---|---|
| `mineru-pdf-workflow` 仍可能按端口 kill ModelPad 托管的 `pdf` 服务 | 用户在 `/Users/jafish/Documents/work/mineru-pdf-workflow` 项目处理，使其完全依赖 ModelPad 托管服务 | modelpad-workflow-compat | 是 | 待外部项目处理 |

## 完成证据

| 计划 | 阶段 | 证据 |
|---|---|---|
| modelpad-v1 | 阶段 0：治理初始化 | `docs/PLAN_MAP.md` 和 `docs/plans/modelpad-v1.md` 已建立；现状快照见 [Step 0 证据](plans/modelpad-v1.md#step-0-证据)。 |
| modelpad-v1 | 阶段 1：项目骨架、数据模型和配置持久化 | Swift Package 已建立（`Package.swift`），全部 29 个单元测试通过（2026-06-30T23:33 UTC+8）。详见 [阶段 1 完成证据](plans/modelpad-v1.md#阶段-1-完成证据)。 |
| modelpad-v1 | 阶段 2：进程托管、状态机、健康检查和日志缓冲 | 新增 LogBuffer、TCPHealthChecker、ModelProcessManager；62 个测试全部通过（29 回归 + 33 新增，2026-06-30T23:52 UTC+8）。详见 [阶段 2 完成证据](plans/modelpad-v1.md#阶段-2-完成证据)。 |
| modelpad-v1 | 阶段 3：本地 HTTP API | 新增 APIDTOs、APIServer（SwiftNIO）；83 个测试全部通过（62 回归 + 21 新增，2026-07-01 UTC+8）。详见 [阶段 3 完成证据](plans/modelpad-v1.md#阶段-3-完成证据)。 |
| modelpad-v1 | 阶段 4：SwiftUI 主面板和菜单栏 | 新增 macOS App 骨架 + 10 ViewModel/装配测试；93 测试通过（83 回归 + 10 新增）；手动验收已闭环。详见 [阶段 4 完成证据](plans/modelpad-v1.md#阶段-4-完成证据)。 |
| modelpad-v1 | 阶段 5：集成验收、菜单栏退出和空闲功耗优化 | 菜单栏左键/右键交互已修复并由用户确认；CPU/功耗由用户确认无问题；智能降频轮询已实现；构建+93 测试通过。详见 [阶段 5 完成证据](plans/modelpad-v1.md#阶段-5-完成证据)。 |
| modelpad-v1 | 阶段 6：macOS `.app` 启动入口和日志展示精简 | 新增 `App/Resources/Info.plist`、`App/Resources/ModelPad.icns`、`scripts/build_app.sh`；`dist/ModelPad.app` ad-hoc 签名可运行并包含自定义图标；`LogView` 移除 stream tag 只保留颜色；93 测试通过。详见 [阶段 6 完成证据](plans/modelpad-v1.md#阶段-6-完成证据)。 |
| modelpad-menu-bar-agent | 阶段 1：菜单栏交互调整和隐藏程序坞 | `LSUIElement=true` 已加入源码和 `.app`；菜单栏 icon 左键下拉菜单包含 `显示面板` / `退出`；右键事件路径已移除；用户已完成手动验收。详见 [阶段 1 完成证据](plans/modelpad-menu-bar-agent.md#阶段-1-完成证据)。 |

## 阶段 5 输入

| 日期 | 类型 | 摘要 | 证据 |
|---|---|---|---|
| 2026-07-02 | 缺陷诊断 | `Cmd+Q`、日志切换、启动阻塞问题诊断；部分问题已由用户修复，仍需纳入阶段 5 验收。 | [阶段 5 缺陷诊断报告](reports/stage5-bug-diagnosis-2026-07-02.md) |
| 2026-07-02 | 新需求 | 菜单栏左键打开面板；右键菜单显示“显示面板”“退出”；退出不提示，直接结束 App 并停止全部托管模型。 | [阶段 5 当前阶段](plans/modelpad-v1.md#当前阶段) |
| 2026-07-02 | 性能问题 | 未启动模型时功耗约 40W、CPU 300%+，需要阶段 5 建立空闲功耗基线并优化。 | [阶段 5 当前阶段](plans/modelpad-v1.md#当前阶段) |

## 后续候选输入

| 日期 | 阶段 | 类型 | 摘要 | 参考 |
|---|---|---|---|---|
| 2026-07-02 | 阶段 6 | 新需求 | 参考 TranslateBar 的 `.app` 启动方式，为 ModelPad 增加可从 Finder / 应用列表启动的标准 macOS App 入口。 | `/Users/jafish/Documents/work/TranslateBar/README.md` |
| 2026-07-02 | 阶段 6 | 新需求 | 日志列表移除 `错误`、`输出` 等 stream tag，只展示实际日志内容。 | [阶段 6 候选](plans/modelpad-v1.md#阶段-6-候选macos-app-启动入口应用列表集成和日志展示精简) |
| 2026-07-03 | 新计划 | 性能优化 | `LogBuffer.append` 当前在锁内使用 `removeFirst` 触发 O(n) 数组移位；按 `deep-jingling-pike.md` 改为环形缓冲，并优先排在外部工作流兼容和菜单栏配置增强之前。 | [ModelPad LogBuffer 性能优化](plans/modelpad-logbuffer-performance.md)；`/Users/jafish/.claude/plans/deep-jingling-pike.md` |
| 2026-07-02 | 新计划 | 兼容性问题 | `pdf` 模型由 ModelPad 托管监听 9000 时，`mineru-pdf-workflow/scripts/pdf-seg` 复用端口后会按端口 kill 服务，导致托管模型被外部 workflow 误杀；已决策由用户在 `mineru-pdf-workflow` 项目处理，使其完全依赖 ModelPad 托管服务。 | [ModelPad 外部工作流兼容](plans/modelpad-workflow-compat.md)；`/Users/jafish/Documents/work/mineru-pdf-workflow/docs/run-summary-2026-07-02.md` |
| 2026-07-03 | 新计划 | 新需求 | ModelPad 像 TranslateBar 一样不出现在程序坞，只作为菜单栏常驻 App 运行。 | [ModelPad 菜单栏常驻和启动配置增强](plans/modelpad-menu-bar-agent.md)；`/Users/jafish/Documents/work/TranslateBar` |
| 2026-07-03 | 后续阶段 | 新需求 | 配置中增加 Python 脚本启动配置，因为现有模型会依赖 py 脚本启动；需兼容现有 `command` 配置。 | [配置编辑弹窗和 Python 脚本启动配置](plans/modelpad-menu-bar-agent.md#阶段-2-候选配置编辑弹窗和-python-脚本启动配置) |
| 2026-07-03 | 后续阶段 | 交互变更 | 菜单栏 icon 左键点击出现下拉菜单，把原右键 `显示面板` / `退出` 功能放到左键，移除右键事件。 | [菜单栏交互调整和隐藏程序坞](plans/modelpad-menu-bar-agent.md#阶段-1-候选菜单栏交互调整和隐藏程序坞) |
| 2026-07-03 | 后续阶段 | UI 调整 | 模型右侧详情界面只保留操作和日志；右上角悬浮设置按钮打开弹窗，在弹窗内编辑模型配置。 | [配置编辑弹窗和 Python 脚本启动配置](plans/modelpad-menu-bar-agent.md#阶段-2-候选配置编辑弹窗和-python-脚本启动配置) |
| 2026-07-03 | 后续阶段 | UI 调整 | 移除面板顶部右上角的启动和停止入口，避免和模型详情内操作重复。 | [配置编辑弹窗和 Python 脚本启动配置](plans/modelpad-menu-bar-agent.md#阶段-2-候选配置编辑弹窗和-python-脚本启动配置) |
| 2026-07-03 | 阶段 3 | 新需求 | 模型设置的引擎选项中增加 `MLX`，因为现有 `Engine` 只有 `ollama`、`llamacpp`、`vllm`、`custom`，但已有模型使用 `mlx_lm.server`。 | [MLX 引擎选项和 API 启停后的 UI 状态同步](plans/modelpad-menu-bar-agent.md#阶段-3-候选mlx-引擎选项和-api-启停后的-ui-状态同步) |
| 2026-07-03 | 阶段 3 | 缺陷修复 | 通过本地 HTTP API 对模型进行启动、停止或重启后，主面板状态不会实时变化；阶段 3 需要在 API 启停路径和 `AppViewModel.refreshStatus()` 之间建立同步机制，同时不回退空闲功耗优化。 | [MLX 引擎选项和 API 启停后的 UI 状态同步](plans/modelpad-menu-bar-agent.md#阶段-3-候选mlx-引擎选项和-api-启停后的-ui-状态同步) |
| 2026-07-03 | 阶段 3 | 真实验收 | 阶段 3 末尾需要启动真实 `dist/ModelPad.app`，用默认 `9786` 端口 curl 验证允许接口、禁止配置写入接口、敏感字段不泄露、API 启停后的 UI 状态同步，以及退出后端口和模型进程无残留。 | [真实运行验收](plans/modelpad-menu-bar-agent.md#验证方式) |
| 2026-07-03 | 新计划 | 性能优化 | `pdf` 模型当前只配置 `PYENV_ROOT` 和基础启动参数；服务端相关 MinerU 环境变量仍主要出现在外部 workflow 中，常驻服务启动后不会受后续 workflow env 影响。 | [ModelPad PDF 模型优化方案](plans/modelpad-pdf-model-optimization.md) |
