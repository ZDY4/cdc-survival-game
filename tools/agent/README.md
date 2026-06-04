# Agent Tools

本目录收纳 repo-local agent workflow 的脚本入口。

Agent 不应把这些脚本当成“可选附加物”，而应优先把它们视为标准工作流的一部分。

## Discovery Rules

- 处理内容编辑、复核、editor 跳转时，先读本文件，再按需读 `docs/agent-workflows/*.md`。
- 若脚本支持 PowerShell help，先执行 `Get-Help tools/agent/<script>.ps1` 看参数和示例。
- 优先复用这里已有脚本，不要重复发明新的 editor 启动或 handoff 流程。

## Current Default

当前默认走 Godot 工具链：

- 内容定位、摘要、引用、校验、格式化和 diff 摘要：`godot-content.ps1`
- Godot import/cache 预热和 GDScript 静态解析：`test-godot-static.ps1`
- Agent 可读的 Godot 脚本 / scene 汇总报告：`godot-agent-report.ps1`
- Godot editor handoff：`open-godot-editor.ps1`
- Godot editor smoke：`test-godot-editor.ps1`
- 地图空间复核：`review-godot-map-visual.ps1`
- 游戏运行时 smoke：`test-godot-game.ps1`
- 手动运行 / 打开 editor / 全量内容校验：根目录 `run_godot_game.bat`、`run_godot_editor.bat`、`run_godot_validate.bat`

`test-godot-static.ps1` 和 `godot-agent-report.ps1` 吸收自 `CODEXVault_GODOT` 的精简思路：保留 headless 验证循环和 agent 汇总报告，不迁入 Linux setup、Godot Mono / .NET、pre-commit、GitHub Pages 或大体积静态工具资产。

## Tools

### `test-godot-static.ps1`

用途：

- 运行 Godot headless import/cache 预热和 GDScript 静态解析检查。

何时使用：

- 修改 `.gd`、`.tscn`、autoload、project 设置或资源引用后，需要比单个 smoke 更基础的 Godot 静态验证。
- 怀疑 Godot import cache、script-class cache 或 GDScript parse 阶段有问题时。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-static.ps1
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario Import
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly
```

行为：

- `Import` 固定调用 `D:\godot\godot.cmd --headless --editor --import --quit --path godot`。
- `CheckOnly` 会遍历 `godot/**/*.gd`，逐个调用 `D:\godot\godot.cmd --headless --path godot --check-only --script res://...`。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/godot_static/<timestamp>/`。

### `godot-agent-report.ps1`

用途：

- 生成 agent 可读的 Godot GDScript 和 scene 结构报告。

何时使用：

- 需要快速理解 Godot 脚本的 `class_name`、`extends`、preload 和 const 分布。
- 需要快速理解 `godot/scenes/**/*.tscn` 的节点层级、脚本引用和实例资源引用，尤其是地图 scene。
- 需要把 Godot 工程结构整理成 `.local` 下的临时报告，而不污染 `godot/` 工程目录。

示例：

```powershell
pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scripts
pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scenes
pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind All -IncludeSource
```

行为：

- `Scripts` 输出 `.gd` 摘要 JSON / Markdown。
- `Scenes` 输出 `godot/scenes/**/*.tscn` / `.scn` 摘要 JSON / Markdown。
- `-IncludeSource` 只额外生成脚本源码汇总文本。
- 所有输出写入 `.local/agent-reports/godot/<timestamp>/`。

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
- `CDC Agent Handoff` 窗口会读取目标内容摘要和引用预览。
- CDC 数据编辑器从 Godot `Tools` 菜单以独立窗口打开，覆盖 `item` / `recipe` / `character` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld`，并显示记录级校验状态、详情和可编辑字段清单。
- 内容保存边界已收口到 `godot/scripts/data/content_edit_service.gd`；当前表单保存覆盖非地图内容的安全元数据字段、`settlement` 的 service rule 字段，以及 `overworld` 的 travel rule 字段。地图布局编辑应使用 Godot 场景编辑器，插件内只保留 `CDC Map Review` 复核和打开 scene 的入口。
- 若 `CDC Agent Handoff` 已有最近 session，会复用现有 Godot editor。
- 若没有最近 session，则启动 `D:\godot\godot.cmd --editor --path godot`。

### `review-godot-map-visual.ps1`

用途：

- 为地图改动提供 Godot 迁移路径下的标准化复核入口。

何时使用：

- `godot/scenes/maps/*.tscn` 或地图兼容数据已被修改，需要验证 Godot loader、地图摘要、引用、世界快照和生成场景链路。
- 需要复核地图空间结果，优先走 Godot 工具链和 `CDC Map Review` dock。

示例：

```powershell
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01 -NoSmoke
```

行为：

- 先通过 `godot-content.ps1` 串行执行 `locate map`、`summarize map`、`references map` 和 `validate changed`；其中 `locate map` / `summarize map` 读取 `godot/scenes/maps/*.tscn`，引用和兼容校验仍会覆盖迁移期 `data/maps` 备份。
- 默认继续运行目标地图的 `map_preview_smoke.gd`，再调用 `test-godot-game.ps1 -Scenario World` 和 `test-godot-game.ps1 -Scenario Scene` 做全局 runtime 回归。
- 输出 Godot map review checklist。
- 进入 Godot editor 后，`CDC Map Review` dock 可显示地图复核信息，并打开对应 `godot/scenes/maps/*.tscn` 供 Godot 场景编辑器维护布局。

### `godot-content.ps1`

用途：

- 通过 Godot headless content CLI 执行内容定位、摘要、引用、校验、格式化和 diff 摘要，作为 `content_tools` 的迁移替代入口。

何时使用：

- 需要通过 Godot 工具链检查 `data/` 内容。
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
- `map locate` 和 `map summarize` 以 `godot/scenes/maps/*.tscn` 为主来源，便于地图布局继续按 Godot scene 工作流维护。
- `validate` 对 `item` / `recipe` / `character` / `map` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld` 执行记录级诊断，输出 `relative_path`、`status` 和字段级 issue；`validate changed` 会批量检查这些已迁移编辑内容。
- `references` 当前覆盖 `item` / `recipe` / `character` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld` / `map`，用于替代旧 `content_tools` 的常用引用查询。
- `format` 覆盖 `item` / `recipe` / `character` / `map` / `dialogue` / `quest` / `skill` / `skill_tree` / `settlement` / `overworld`，只重排 JSON 空白，不通过 Godot Dictionary 重写字段顺序或数字字面量。

### `test-godot-editor.ps1`

用途：

- 运行 Godot editor 侧的 agent smoke 测试。

何时使用：

- 修改 Godot editor plugin、handoff、独立内容编辑窗口、map review 或内容保存服务后。
- 需要一条命令复核 Godot editor 工具面是否仍能读取、展示、编辑和复核内容。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario EditorHandoff
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario ContentEditors
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario MapReview
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario ContentEdit
```

行为：

- 固定调用 `D:\godot\godot.cmd --headless --path godot --script <smoke>`。
- 默认 `-Scenario All` 会运行所有 Godot editor headless smoke。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/godot_editor/<timestamp>/`。

### `test-godot-game.ps1`

用途：

- 运行 Godot runtime / game 的 agent smoke 测试。

何时使用：

- 修改 Godot runtime、世界生成、shader、交互、UI、任务、战斗或存档后。
- 需要一条命令复核当前 Godot 可玩闭环。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario MigrationGuard
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario HeadlessNewGame
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario HeadlessWorld
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario MainMenu
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContentCLI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContentEdit
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario EditorHandoff
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContentEditors
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario MapReview
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario FogShader
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Overworld
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Movement
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Interaction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario DialogueAction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContainerUI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Equipment
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Crafting
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Save
```

行为：

- 固定调用 `D:\godot\godot.cmd --headless --path godot --script <smoke>`；`HeadlessNewGame` / `HeadlessWorld` 通过 `godot/scripts/app/headless_runner.gd` 覆盖 headless 启动入口。
- `MigrationGuard` 调用 `godot/scripts/tools/mainline_migration_guard.gd`，用于确认 Godot 版本为 `4.6.3`，且主线未重新引入 Rust / Cargo / Bevy 时代源码文件。
- 默认 `-Scenario All` 会运行所有已迁移 Godot smoke。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/godot_game/<timestamp>/`。

## Maintenance Rule

- 新增脚本时，至少补齐：
  - 这个 README 的用途和示例
  - 脚本自身的 comment-based help
  - 对应的 `docs/agent-workflows/*.md`
