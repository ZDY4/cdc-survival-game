# Agent Workflows

本目录定义仓库内 AI Agent 的内容修改主路径。

目标：

- 不再以 Bevy editor 内聊天窗口作为 AI 入口
- 让 Codex / OpenCode 一类 Agent 直接在仓库中读写数据
- 统一通过 Godot 迁移工具链做校验、格式化、摘要和 editor 复核

## Workflow List

- `edit-item.md`
- `edit-recipe.md`
- `edit-character.md`
- `edit-map.md`
- `review-map-visual.md`
- `review-godot-map-visual.md`
- `test-bevy-game.md`
- `test-godot-editor.md`
- `test-godot-game.md`

## General Rules

1. 先定位目标文件，再读相关依赖和约束，不要直接盲改。
2. 修改后必须跑最小校验；若当前仓库存在已知编译阻塞，需要在结果里明确说明。
3. 地图类改动默认优先使用 Godot map review 入口做空间复核；Bevy editor 仅保留为旧行为对照。
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
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario BevyEquivalence`

旧 Rust/Bevy 对照入口仅在需要行为差异分析时使用：

- `cargo run -p content_tools -- locate <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- validate <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- validate changed`
- `cargo run -p content_tools -- summarize <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- references <item|map> <id>`
- `cargo run -p content_tools -- format <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- format changed`
- `cargo run -p content_tools -- diff-summary --path <file>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Item <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Recipe <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Dialogue <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Quest <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Map <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Character <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/review-map-visual.ps1 -Map <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1`
- `cargo check -p game_editor -p bevy_item_editor -p bevy_recipe_editor -p bevy_dialogue_editor -p bevy_quest_editor -p bevy_map_editor -p content_tools`

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

旧 Bevy editor 对照入口：

- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Item <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Recipe <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Dialogue <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Quest <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Character <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Map <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/review-map-visual.ps1 -Map <id>`

游戏 smoke 复核：

- `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1`
- `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario All`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All`
- `pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1`
- `pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1 -Scenario WorldInteractionMenu`

Godot 迁移期间，运行时/游戏闭环优先跑 `test-godot-game.ps1`；Bevy smoke 保留为旧客户端行为对照。

Godot editor 迁移期复核优先跑 `test-godot-editor.ps1`；旧 Bevy editor 聚合 smoke 仅作为行为差异对照。

`BevyEquivalence` 场景会输出旧 Bevy `WorldInteractionMenu` 到 Godot smoke 的机器可读覆盖映射，用于证明拾取目标选择、HUD 交互提示、primary pickup option、执行拾取和消费节点移除已经在 Godot 侧闭环。

Godot 迁移期间，内容定位、摘要、引用、格式化、diff 摘要和全量校验优先跑 `godot-content.ps1`；Rust `content_tools` 保留为旧基线和差异对照。

当前 handoff 行为：

- Godot `CDC Agent Handoff` dock 会写 `tmp/editor_handoff/godot_editor.session.json`
- `open-godot-editor.ps1` 会写 `tmp/editor_handoff/godot_editor.navigation.json`
- Godot `CDC Content Browser` dock 会浏览 `item` / `recipe` / `character` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld` / `map`，显示过滤列表、记录级校验状态、详情摘要和可编辑字段清单
- `godot/scripts/data/content_edit_service.gd` 是迁移期内容保存边界；后续 Godot 表单 UI 必须通过该服务写回 JSON
- 当前表单保存覆盖 `item` / `recipe` / `character` / `map` / `dialogue` / `quest` / `skill` / `skill_tree` 的安全元数据字段、`settlement` 的 service rule 字段，以及 `overworld` 的 travel rule 字段
- `item` / `recipe` / `character` / `map` 目标会显示只读 `edit_plan`，列出可编辑字段组、引用影响和保存后复核 checklist
- `map` 目标额外显示 `map_review` 和 `map_review_checks`，用于替代旧 Bevy map editor 的基础空间复核摘要
- 若对应 editor 最近处于活跃状态，会优先复用现有实例
- 脚本会把目标 id 写入 `tmp/editor_handoff/*.navigation.json`
- editor 会读取 handoff 请求并切换到目标记录
- 脚本会 best-effort 尝试前置该 editor 窗口；前置失败不影响选中请求
- 若没有最近活跃实例，则直接启动 editor，并通过启动参数选中目标

地图视觉复核辅助：

- `review-godot-map-visual.ps1` 会先通过 Godot content CLI 执行 `locate` / `summarize` / `references` / `validate changed`
- 默认继续运行 Godot `World` 和 `Scene` smoke，确认地图数据能进入世界快照和生成场景链路
- Godot 迁移期间，地图改动优先使用 `review-godot-map-visual.ps1`
- `legacy/bevy/agent/review-map-visual.ps1` 会先串行执行 `locate` / `summarize` / `references` / `validate`
- 随后输出固定的视觉复核 checklist
- 默认会继续调用 `legacy/bevy/agent/open-editor.ps1 -Map <id>` 打开或复用 `bevy_map_editor`
