# AGENTS.md

## 本机补充说明

- 如果仓库根目录存在 `AGENTS.local.md`，agent 在读取本文件后应同时读取该本机补充文件。
- `AGENTS.local.md` 只用于本机路径、工具偏好、临时备注或个人约定；它应加入 `.git/info/exclude`，不要提交到仓库。
- 若 `AGENTS.local.md` 与本文件冲突，以本文件和用户当前指令为准。

## 旧 Rust / Bevy 参考工程

- 旧实现参考副本位于 `G:\Projects\cdc_survival_game_bevy_reference`，检出自本仓库 tag `bevy-pre-strip`，当前 HEAD 为 `be8938e`。
- 该目录只作为迁移期行为、参数和资源组织方式的对照参考；当前仓库仍以 `Godot 4.6.3 + GDScript` 为唯一运行时和开发主线。
- 需要还原旧相机、输入、拾取、渲染、UI、编辑器或工具行为时，优先查看参考副本下的 `rust/apps/bevy_debug_viewer/src/**`、`rust/apps/bevy_map_editor/src/**` 和 `rust/crates/**`，再按 Godot 架构边界重实现。
- 不要把 Rust / Bevy 源码、Cargo 工程或旧 app 重新复制回当前 mainline；参考信息只能转译为 Godot scene、GDScript、数据层或文档。


## 代码组织

- 默认按职责拆分模块，不把新增功能持续堆进单个大文件。
- `project.godot`、autoload、app 入口脚本只承担入口、装配和导出职责；业务逻辑放到独立模块。
- 避免创建无明确边界的 `utils.gd`、`common.gd`、`helpers.gd` 大杂烩；只有职责清晰且稳定复用时才抽公共模块。
- 一个功能同时包含数据读写、规则计算、持久化、UI 展示时，至少拆成数据/规则层和界面/装配层。
- 超过约 `300` 行的业务文件应评估是否拆分；超过约 `500` 行且还要新增业务逻辑时，默认先做最小必要拆分。
- 修改臃肿文件时，只有在本任务直接触及且能保持小范围时才做职责切分。

## 注释与日志

- 非显然业务规则、跨层边界、重要约束或容易误改的逻辑应补充简洁中文注释。
- 避免只复述代码字面含义的低价值注释。
- 关键流程、关键状态变更、重要失败分支应补充可排查的日志，包含资源 id、目标对象、动作类型、失败原因或关键参数。
- 避免无上下文、不可行动或高频刷屏的日志。

## Agent 工具使用

- 处理内容编辑、定位、摘要、引用、格式化、校验时，先看 `tools/agent/README.md`；涉及具体流程时再看 `docs/agent-workflows/*.md`。
- 内容 CLI 默认使用 `tools/agent/godot-content.ps1`。
- 需要 Godot import/cache 预热或 GDScript 静态解析时，使用 `tools/agent/test-godot-static.ps1`。
- 需要给 agent 汇总 Godot 脚本或 scene 结构时，使用 `tools/agent/godot-agent-report.ps1`，报告输出到 `.local/agent-reports/godot`。
- 需要打开或复用 Godot editor 并定位目标时，优先使用 `tools/agent/open-godot-editor.ps1`。
- 地图改动后的空间复核优先使用 `tools/agent/review-godot-map-visual.ps1`；需要人工查看或精修时打开对应 Godot map scene，并用 `CDC Map Review` dock 查看复核信息。
- 游戏运行时 smoke 默认使用 `tools/agent/test-godot-game.ps1`。
- Editor 插件和编辑服务 smoke 默认使用 `tools/agent/test-godot-editor.ps1`。
- runtime smoke / tool 需要驱动等待、世界刷新或视觉刷新时，优先调用 `GameApp.submit_wait_action()`、`GameApp.rebuild_runtime_world()`、`GameApp.refresh_world_visuals()`、`GameApp.finish_world_action_presentations()` 等稳定 facade；不要新增对 `_setup_*`、`_rebuild_*` 等私有入口的依赖。
- 若脚本提供 PowerShell comment-based help，先用 `Get-Help tools/agent/<script>.ps1` 确认参数、示例和副作用。
- 新增 `tools/agent/` 脚本时，同时更新脚本自身 help、`tools/agent/README.md` 和相关 workflow 文档。
- `CODEXVault_GODOT` 仅作为 headless 验证和 agent 汇总思路参考；不要迁入 Linux setup、Godot Mono / .NET、pre-commit、GitHub Pages 或大体积静态工具资产。

## Bug / Crash 排查

- 处理 bug、报错、回归或崩溃时，先识别受影响的 app、tool、scene 或 smoke。
- 若有相关日志，先查看 `logs/` 下最新相关文件，或查看 `tools/agent` / Godot headless smoke 输出，再决定复现和修复路径。
- 日志不足、过期或无关时，应说明这一点，然后继续做最小复现、代码定位或运行验证。
- 纯语法错误、静态类型错误、明显重构任务不强制先查日志。

## 验证与交付

- 不主动新增测试文件，除非用户明确要求；默认用现有 Godot headless smoke、`godot-content.ps1`、`validate_all.gd`、已有运行入口或最小手动 smoke 验证。
- 若无法验证，交付时明确说明未验证项、原因和建议下一步。
- 若修复依赖日志结论，交付时说明使用了哪个日志文件或 smoke 输出、观察到的关键信号、是否完成复现验证。
- 完成涉及文件修改的独立开发任务并通过必要验证后，默认创建一次 Git commit；只暂存并提交与本任务直接相关的文件。纯审查、答疑或探索任务不提交；用户明确要求不提交时也不提交。
- Commit message 使用简体中文，简洁说明变更目的和范围。
