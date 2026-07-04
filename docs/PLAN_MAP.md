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
| [ModelPad LogBuffer 性能优化](plans/modelpad-logbuffer-performance.md) | 已完成 | 阶段 1：环形缓冲替换 | modelpad-v1 | [阶段 1 完成证据](plans/modelpad-logbuffer-performance.md#阶段-1-完成证据) |
| [ModelPad 外部工作流兼容](plans/modelpad-workflow-compat.md) | 已完成 | 阶段 1：`pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容已由外部项目闭环 | modelpad-v1 | [阶段 1 完成证据](plans/modelpad-workflow-compat.md#阶段-1-完成证据) |
| [ModelPad PDF 模型优化方案](plans/modelpad-pdf-model-optimization.md) | 已完成 | 阶段 1：配置层稳定性优化 | modelpad-v1, modelpad-workflow-compat | [阶段 1 完成证据](plans/modelpad-pdf-model-optimization.md#阶段-1-完成证据) |
| [ModelPad 菜单栏常驻和启动配置增强](plans/modelpad-menu-bar-agent.md) | 已完成 | 三个阶段全部闭环 | modelpad-v1 | [阶段 1 证据](plans/modelpad-menu-bar-agent.md#阶段-1-完成证据) / [阶段 2 证据](plans/modelpad-menu-bar-agent.md#阶段-2-完成证据) / [阶段 3 证据](plans/modelpad-menu-bar-agent.md#阶段-3-完成证据) |
| [ModelPad 启动接口环境变量覆盖](plans/modelpad-api-start-env-overrides.md) | 待实施 | 阶段 1：启动接口一次性环境变量覆盖 | modelpad-v1, modelpad-menu-bar-agent | [Step 0 证据](plans/modelpad-api-start-env-overrides.md#step-0-证据) |

允许状态：`候选`、`设计中`、`待实施`、`实施中`、`已完成`、`已替代`、`已合并`、`已废弃`。

## 推荐顺序

1. `modelpad-v1` ✅（全部阶段已完成）
2. `modelpad-logbuffer-performance` ✅（阶段 1 已完成）
3. `modelpad-workflow-compat` ✅（阶段 1 已由 `mineru-pdf-workflow` 外部项目闭环）
4. `modelpad-pdf-model-optimization` ✅（阶段 1 已完成）
5. `modelpad-menu-bar-agent` ✅（三个阶段全部已完成）
6. `modelpad-api-start-env-overrides`（待实施：启动接口一次性环境变量覆盖）

## 依赖关系

| 计划 | 依赖 | 原因 |
|---|---|---|
| modelpad-v1 | - | - |
| modelpad-logbuffer-performance | modelpad-v1 | 依赖阶段 2 已建立的 `LogBuffer`、进程输出捕获和日志测试基础 |
| modelpad-workflow-compat | modelpad-v1 | 依赖 `.app` 启动入口、模型托管、健康检查和退出清理能力已完成 |
| modelpad-pdf-model-optimization | modelpad-v1, modelpad-workflow-compat | 依赖 ModelPad 模型托管能力；验证需避免与外部 workflow 生命周期冲突混淆 |
| modelpad-menu-bar-agent | modelpad-v1 | 依赖 `.app` 启动入口、菜单栏图标、退出流程和打包流程已完成 |
| modelpad-api-start-env-overrides | modelpad-v1, modelpad-menu-bar-agent | 依赖 v1 本地 HTTP API、模型托管、环境变量注入能力，以及后续 Python 脚本环境变量合并能力已完成 |

## 替代、合并和废弃

| 计划 | 关系 | 目标 | 原因 |
|---|---|---|---|
| - | - | - | - |

## 当前阻塞项

| 问题 | 推荐方案 | 影响范围 | 是否阻塞当前阶段 | 状态 |
|---|---|---|---|---|
| - | - | - | 否 | 当前无阻塞项 |

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
| modelpad-menu-bar-agent | 阶段 2：配置编辑弹窗和 Python 脚本启动配置 | 新增 `LaunchMode` / `PythonScriptConfig`；`ModelConfig` 扩展向后兼容；`ModelDetailView` 重写为运行视图；`ModelConfigSheet` 配置弹窗；5 个模型脚本纳入项目；shell 转义修复 + 相对路径校验；106 测试通过；用户手动验收完成。详见 [阶段 2 完成证据](plans/modelpad-menu-bar-agent.md#阶段-2-完成证据)。 |
| modelpad-menu-bar-agent | 阶段 3：MLX 引擎选项和 API 启停 UI 同步 | Engine 新增 `mlx`；API 启停后通过 `onModelStateChanged` 回调即时刷新 UI；107 测试通过；API 实操作验收完成。详见 [阶段 3 完成证据](plans/modelpad-menu-bar-agent.md#阶段-3-完成证据)。 |
| modelpad-logbuffer-performance | 阶段 1：环形缓冲替换 | `LogBuffer` 从 `Array.removeFirst` O(n) 改为预分配定长数组 + `writeIndex` O(1) 环形缓冲；新增 3 个边界测试（单槽、覆写顺序、clear 重置）；110 测试全通过。详见 [阶段 1 完成证据](plans/modelpad-logbuffer-performance.md#阶段-1-完成证据)。 |
| modelpad-workflow-compat | 阶段 1：`pdf` 模型与 `mineru-pdf-workflow` 生命周期兼容 | 用户确认外部项目已完成；`mineru-pdf-workflow` 的 `modelpad-pdf-service-lifecycle` 计划已闭环，`pdf-seg`/`pdf-auto`/`pdf-rerun` 只复用 ModelPad PDF 服务，不再启动、重启、停止或清理共享运行目录。详见 [阶段 1 完成证据](plans/modelpad-workflow-compat.md#阶段-1-完成证据)。 |
| modelpad-pdf-model-optimization | 阶段 1：配置层稳定性优化 | `pdf.env` 已写入 MinerU 服务端环境变量；真实 `pdf` 服务启动后 `/health` 返回 `processing_window_size=8`、`task_retention_seconds=21600`、`max_concurrent_requests=1`；`/docs` 返回 404；停止后 9000 端口释放。该配置更新存在一次未获明确授权的非文档变更偏差，已在专项计划记录，用户已确认保留；用户已完成最小 PDF workflow 手动验收，确认解析可跑通、`9000` 不被误杀、输出目录产生任务输出。详见 [阶段 1 完成证据](plans/modelpad-pdf-model-optimization.md#阶段-1-完成证据)。 |

## 阶段 5 输入

| 日期 | 类型 | 摘要 | 证据 |
|---|---|---|---|
| 2026-07-02 | 缺陷诊断 | `Cmd+Q`、日志切换、启动阻塞问题诊断；部分问题已由用户修复，仍需纳入阶段 5 验收。 | [阶段 5 缺陷诊断报告](reports/stage5-bug-diagnosis-2026-07-02.md) |
| 2026-07-02 | 新需求 | 菜单栏左键打开面板；右键菜单显示“显示面板”“退出”；退出不提示，直接结束 App 并停止全部托管模型。 | [阶段 5 当前阶段](plans/modelpad-v1.md#当前阶段) |
| 2026-07-02 | 性能问题 | 未启动模型时功耗约 40W、CPU 300%+，需要阶段 5 建立空闲功耗基线并优化。 | [阶段 5 当前阶段](plans/modelpad-v1.md#当前阶段) |

## 后续候选输入

| 日期 | 类型 | 摘要 | 吸收计划 |
|---|---|---|---|
| 2026-07-04 | 新需求 | 启动服务接口增加环境变量配置能力，默认作为本次启动的一次性 env 覆盖，不持久化、不通过查询接口泄露。 | [ModelPad 启动接口环境变量覆盖](plans/modelpad-api-start-env-overrides.md) |

历史候选输入已归档：2026-07-02 至 2026-07-03 期间记录的 `.app` 启动入口、日志 tag 移除、LogBuffer 性能优化、外部 workflow 兼容、菜单栏常驻、Python 脚本启动配置、配置弹窗、MLX 引擎和 API 启停 UI 同步等输入，均已被 `modelpad-v1`、`modelpad-logbuffer-performance`、`modelpad-workflow-compat`、`modelpad-menu-bar-agent` 或 `modelpad-pdf-model-optimization` 吸收并完成。

用户已于 2026-07-04 确认不推进 PDF 冷启动优化评估；`modelpad-pdf-model-optimization` 阶段 2 标记为已废弃，保持 `--enable-vlm-preload False`。
