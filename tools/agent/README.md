# Agent Tools

本目录收纳 repo-local agent workflow 的脚本入口。

Agent 不应把这些脚本当成“可选附加物”，而应优先把它们视为标准工作流的一部分。

## Discovery Rules

- 处理内容编辑、复核、editor 跳转时，先读本文件，再按需读 `docs/agent-workflows/*.md`。
- 若脚本支持 PowerShell help，先执行 `Get-Help tools/agent/<script>.ps1` 看参数和示例。
- 优先复用这里已有脚本，不要重复发明新的 editor 启动或 handoff 流程。

## Current Default

迁移期默认走 Godot 工具链：

- 内容定位、摘要、引用、校验、格式化和 diff 摘要：`godot-content.ps1`
- Godot editor handoff：`open-godot-editor.ps1`
- Godot editor smoke：`test-godot-editor.ps1`
- 地图空间复核：`review-godot-map-visual.ps1`
- 游戏运行时 smoke：`test-godot-game.ps1`
- 手动运行 / 打开 editor / 全量内容校验：根目录 `run_godot_game.bat`、`run_godot_editor.bat`、`run_godot_validate.bat`

旧 `open-editor.ps1`、`review-map-visual.ps1` 和 `test-bevy-game.ps1` 只在需要 Rust/Bevy 行为差异对照时使用。

## Tools

### `open-editor.ps1` Legacy

用途：

- 打开或复用现有 Bevy editor，并自动定位到指定 `item` / `recipe` / `dialogue` / `quest` / `character` / `map`。这是旧实现对照入口。

何时使用：

- 需要旧 Bevy editor 作为行为差异对照。
- 需要让旧 editor 直接切到具体目标，而不是手动在列表里查找。

示例：

```powershell
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Item 1001
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Recipe recipe_bandage_basic
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Dialogue trader_lao_wang
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Quest zombie_hunter
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Character scavenger_maya
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Map forest
```

行为：

- 若对应 editor 最近处于活跃状态，会优先复用现有实例。
- 脚本会写 `tmp/editor_handoff/*.navigation.json` 让运行中的 editor 切换选中目标。
- 会 best-effort 尝试前置 editor 窗口；前置失败不影响 handoff。
- 若没有最近活跃实例，则直接启动对应 editor，并通过启动参数选中目标。

### `open-godot-editor.ps1`

用途：

- 打开或复用 Godot editor，并把指定 `item` / `recipe` / `dialogue` / `quest` / `character` / `skill` / `skill_tree` / `settlement` / `overworld` / `map` 写入 Godot editor handoff dock。

何时使用：

- 已完成数据修改，需要进入 Godot editor 做迁移期复核。
- 需要验证 Godot editor 插件能读取目标内容和 handoff 请求。

示例：

```powershell
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Item 1001
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Recipe recipe_bandage_basic
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Dialogue trader_lao_wang
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Quest tutorial_survive
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Character scavenger_maya
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Skill survival
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -SkillTree survival
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Settlement survivor_outpost_01_settlement
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Overworld main_overworld
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map survivor_outpost_01
```

行为：

- 写入 `tmp/editor_handoff/godot_editor.navigation.json`。
- `CDC Agent Handoff` dock 会读取目标内容摘要和引用预览。
- `CDC Content Browser` dock 会在 Godot editor 内浏览 `item` / `recipe` / `character` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld` / `map`，并显示记录级校验状态、详情和可编辑字段清单。
- 内容保存边界已收口到 `godot/scripts/data/content_edit_service.gd`；当前表单保存覆盖 `item` / `recipe` / `character` / `map` / `dialogue` / `quest` / `skill` / `skill_tree` 的安全元数据字段、`settlement` 的 service rule 字段，以及 `overworld` 的 travel rule 字段。
- 若 `CDC Agent Handoff` dock 已有最近 session，会复用现有 Godot editor。
- 若没有最近 session，则启动 `D:\godot\godot.cmd --editor --path godot`。

### `review-map-visual.ps1` Legacy

用途：

- 为地图改动提供旧 Bevy 路径的标准化视觉复核入口。

何时使用：

- Godot map review 结果与旧实现疑似不一致，需要旧 Bevy 路径做行为对照。
- 需要把旧“map 校验 + visual review”压成一个固定命令，而不是手动拼多条命令。

示例：

```powershell
pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map forest
pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map factory -NoOpenEditor
```

行为：

- 先在 `rust/` workspace 下串行执行：
  - `cargo run -q -p content_tools -- locate map <id>`
  - `cargo run -q -p content_tools -- summarize map <id>`
  - `cargo run -q -p content_tools -- references map <id>`
  - `cargo run -q -p content_tools -- validate map <id>`
- 然后输出固定 visual review checklist。
- 默认继续调用 `open-editor.ps1 -Map <id>` 打开或复用 `bevy_map_editor`。
- 若使用 `-NoOpenEditor`，则只输出 CLI 复核信息，不启动 editor。

### `review-godot-map-visual.ps1`

用途：

- 为地图改动提供 Godot 迁移路径下的标准化复核入口。

何时使用：

- `data/maps/*.json` 已被修改，需要验证 Godot loader、地图摘要、引用、世界快照和生成场景链路。
- 需要替代旧 `bevy_map_editor` 视觉复核依赖，优先走 Godot 工具链和 `CDC Map Preview` dock。

示例：

```powershell
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01 -NoSmoke
```

行为：

- 先通过 `godot-content.ps1` 串行执行 `locate map`、`summarize map`、`references map` 和 `validate changed`。
- 默认继续运行目标地图的 `map_preview_smoke.gd`，再调用 `test-godot-game.ps1 -Scenario World` 和 `test-godot-game.ps1 -Scenario Scene` 做全局 runtime 回归。
- 输出 Godot map review checklist；当前不打开旧 Bevy editor。
- 进入 Godot editor 后，`CDC Map Preview` dock 可选择地图对象并通过 Godot data 层编辑位置、footprint、旋转和阻挡字段。

### `godot-content.ps1`

用途：

- 通过 Godot headless content CLI 执行内容定位、摘要、引用、校验、格式化和 diff 摘要，作为 `content_tools` 的迁移替代入口。

何时使用：

- 需要在不进入 Rust workspace 的情况下检查 `data/` 内容。
- 需要验证 Godot loader 对当前内容的读取、摘要、引用和格式化结果。

示例：

```powershell
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command locate -Kind item -Id 1006
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind map -Id survivor_outpost_01
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind dialogue -Id trader_lao_wang_intro
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind skill_tree -Id survival
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind item -Id 1006
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind quest -Id tutorial_survive
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind item -Id 1006
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind dialogue -Id trader_lao_wang_intro
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind skill_tree -Id survival
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind settlement -Id survivor_outpost_01_settlement
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind overworld -Id main_overworld
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command diff-summary -Kind path -Id data/items/1006.json
```

行为：

- 固定调用 `D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/content_cli.gd -- ...`。
- 当前覆盖 `locate` / `summarize` / `references` / `validate` / `validate changed` / `format` / `format changed` / `diff-summary`。
- `summarize` 输出 `item` / `recipe` / `character` / `map` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld` 的高信号字段摘要。
- `validate` 对 `item` / `recipe` / `character` / `map` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld` 执行记录级诊断，输出 `relative_path`、`status` 和字段级 issue；`validate changed` 会批量检查这些已迁移编辑内容。
- `references` 当前覆盖 `item` / `recipe` / `character` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld` / `map`，用于替代旧 `content_tools` 的常用引用查询。
- `format` 覆盖 `item` / `recipe` / `character` / `map` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld`，只重排 JSON 空白，不通过 Godot Dictionary 重写字段顺序或数字字面量。

### `test-bevy-game.ps1` Legacy

用途：

- 运行 Bevy game 的 agent smoke 测试，验证可自动进入确定的 gameplay runtime 并检查关键交互链路。

何时使用：

- 修改 `bevy_debug_viewer` 输入、picking、交互菜单、运行时 prompt 或世界交互 UI 后。
- 需要确认 agent 可以用一条命令复核“右键可交互目标会打开交互菜单”。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-bevy-game.ps1
pwsh -NoProfile -File tools/agent/test-bevy-game.ps1 -Scenario WorldInteractionMenu
```

行为：

- 在 `rust/` workspace 下运行目标 `cargo test`。
- 当前 `WorldInteractionMenu` 场景会构造固定 gameplay runtime、选中玩家、定位 pickup 目标，并断言交互菜单和 prompt 正常。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/bevy_game/<timestamp>/`。

### `test-godot-editor.ps1`

用途：

- 运行 Godot editor 迁移侧的 agent smoke 测试，作为旧 Bevy editor 聚合 smoke 的迁移替代入口。

何时使用：

- 修改 Godot editor plugin、handoff、content browser、map preview、内容保存服务或地图编辑服务后。
- 需要一条命令复核 Godot editor 迁移期工具面是否仍能读取、展示、编辑和预览内容。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario EditorHandoff
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario ContentBrowser
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario MapPreview
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario ContentEdit
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario MapEdit
```

行为：

- 固定调用 `D:\godot\godot.cmd --headless --path godot --script <smoke>`。
- 默认 `-Scenario All` 会运行所有 Godot editor headless smoke。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/godot_editor/<timestamp>/`。

### `test-godot-game.ps1`

用途：

- 运行 Godot runtime / game 的 agent smoke 测试，作为 Bevy game smoke 的迁移替代入口。

何时使用：

- 修改 Godot runtime、世界生成、shader、交互、UI、任务、战斗或存档后。
- 需要一条命令复核当前 Godot 可玩闭环。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario HeadlessNewGame
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario HeadlessWorld
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContentCLI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContentEdit
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario MapEdit
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario EditorHandoff
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario EditorBrowser
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario MapPreview
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario FogShader
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Overworld
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Movement
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Interaction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario BevyEquivalence
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario DialogueAction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContainerUI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Equipment
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Crafting
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Save
```

行为：

- 固定调用 `D:\godot\godot.cmd --headless --path godot --script <smoke>`；`HeadlessNewGame` / `HeadlessWorld` 通过 `godot/scripts/app/headless_runner.gd` 覆盖迁移后的 Bevy server/headless 替代入口。
- 默认 `-Scenario All` 会运行所有已迁移 Godot smoke。
- `BevyEquivalence` 会输出旧 Bevy `WorldInteractionMenu` 到 Godot smoke 的机器可读覆盖映射，并直接复核 pickup prompt、HUD 交互行、primary option、拾取执行和节点消费。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/godot_game/<timestamp>/`。

## Maintenance Rule

- 新增脚本时，至少补齐：
  - 这个 README 的用途和示例
  - 脚本自身的 comment-based help
  - 对应的 `docs/agent-workflows/*.md`
