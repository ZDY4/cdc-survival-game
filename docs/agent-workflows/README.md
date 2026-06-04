# Agent Workflows

本目录定义仓库内 AI Agent 的内容修改主路径。

目标：

- 让 Codex / OpenCode 一类 Agent 直接在仓库中读写数据
- 统一通过 Godot 工具链做校验、格式化、摘要和 editor 复核

## Workflow List

- `edit-item.md`
- `edit-recipe.md`
- `edit-character.md`
- `edit-map.md`
- `godot-agent-report.md`
- `review-godot-map-visual.md`
- `test-godot-editor.md`
- `test-godot-game.md`
- `test-godot-static.md`

## General Rules

1. 先定位目标文件，再读相关依赖和约束，不要直接盲改。
2. 修改后必须跑最小校验；若当前仓库存在已知编译阻塞，需要在结果里明确说明。
3. 地图类改动默认优先使用 Godot map review 入口做空间复核。
4. `item / recipe / character` 优先直接改数据文件，不要依赖 editor 内 AI 入口。
5. 不要在 editor 里重建新的 AI 聊天窗口或 provider 设置页。

## Current Validation Baseline

当前优先使用：

- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command locate -Kind <item|recipe|character|dialogue|quest|skill|skill_tree|settlement|overworld|map> -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind <item|recipe|character|map> -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind <item|recipe|character|dialogue|quest|skill|skill_tree|settlement|overworld|map> -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind <item|recipe|character|dialogue|quest|skill|skill_tree|settlement|overworld|map> -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind changed`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command diff-summary -Kind path -Id <file>`
- `pwsh -NoProfile -File tools/agent/test-godot-static.ps1`
- `pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario Import`
- `pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly`
- `pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scripts`
- `pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scenes`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Item <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Recipe <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Dialogue <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Quest <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Character <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Skill <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -SkillTree <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Settlement <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Overworld <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map <id>`
- `pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map <id>`
- `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1`
- `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario All`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All`

## Editor Handoff

当修改已经完成，需要进入 Godot editor 做迁移期复核或手工精修时，优先使用：

- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Item <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Recipe <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Dialogue <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Quest <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Character <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Skill <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -SkillTree <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Settlement <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Overworld <id>`
- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map <id>`

游戏 smoke 复核：

- `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1`
- `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario All`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All`

运行时/游戏闭环优先跑 `test-godot-game.ps1`。

Godot editor 复核优先跑 `test-godot-editor.ps1`。

内容定位、摘要、引用、格式化、diff 摘要和全量校验优先跑 `godot-content.ps1`。

Godot import/cache 预热和 GDScript 静态解析优先跑 `test-godot-static.ps1`。

需要 agent 快速理解 Godot 脚本和 scene 结构时，优先跑 `godot-agent-report.ps1`；报告只写入 `.local/agent-reports/godot`。

`test-godot-static.ps1` 和 `godot-agent-report.ps1` 只迁移 `CODEXVault_GODOT` 中适合本项目的精简工作流，不迁入 Linux setup、Godot Mono / .NET、pre-commit、GitHub Pages 或大体积静态工具资产。

当前 handoff 行为：

- Godot `CDC Agent Handoff` 窗口会写 `tmp/editor_handoff/godot_editor.session.json`
- `open-godot-editor.ps1` 会写 `tmp/editor_handoff/godot_editor.navigation.json`
- Godot `Tools` 菜单提供独立 CDC 数据编辑窗口，覆盖 `item` / `recipe` / `character` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld`，显示过滤列表、记录级校验状态、详情摘要和可编辑字段清单
- `godot/scripts/data/content_edit_service.gd` 是迁移期内容保存边界；后续 Godot 表单 UI 必须通过该服务写回 JSON
- 当前表单保存覆盖 `item` / `recipe` / `character` / `dialogue` / `quest` / `skill` / `skill_tree` 的安全元数据字段、`settlement` 的 service rule 字段，以及 `overworld` 的 travel rule 字段
- `item` / `recipe` / `character` 目标会显示只读 `edit_plan`，列出可编辑字段组、引用影响和保存后复核 checklist
- `map` 目标通过 `CDC Map Review` 复核窗口查看 `map_review` 和 `map_review_checks`，并从窗口打开对应 Godot map scene
- 若对应 editor 最近处于活跃状态，会优先复用现有实例
- 脚本会把目标 id 写入 `tmp/editor_handoff/*.navigation.json`
- editor 会读取 handoff 请求并切换到目标记录
- 脚本会 best-effort 尝试前置该 editor 窗口；前置失败不影响选中请求
- 若没有最近活跃实例，则直接启动 editor，并通过启动参数选中目标

地图视觉复核辅助：

- `review-godot-map-visual.ps1` 会先通过 Godot content CLI 执行 `locate` / `summarize` / `references` / `validate changed`
- 默认继续运行 Godot `World` 和 `Scene` smoke，确认地图数据能进入世界快照和生成场景链路
- 地图改动优先使用 `review-godot-map-visual.ps1`
