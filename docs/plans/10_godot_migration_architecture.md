# Godot 4.6.3 迁移完成记录

## 当前状态

本仓库已经完成向 `Godot 4.6.3 + GDScript` 的主线迁移。当前可运行、可验证、可编辑的默认工程只依赖：

- Godot 命令行入口：`D:\godot\godot.cmd`
- Godot 工程目录：`godot/`
- 内容输入源：仓库根目录 `data/`
- agent 工具入口：`tools/agent/*.ps1`
- 默认启动脚本：`run_godot_game.bat`、`run_godot_editor.bat`、`run_godot_validate.bat`

旧运行时、旧 workspace、旧启动脚本、旧 shader、旧 workflow 文档和旧 smoke 产物已从当前树移除。历史实现只通过 Git 历史追溯，不再作为仓库内的运行、验证或对照依赖。

已验证 Godot 版本：

```text
4.6.3.stable.official.7d41c59c4
```

## 架构边界

- `data/` 中的 JSON 是当前内容权威输入源。
- `godot/scripts/data/` 负责内容路径、JSON 加载、registry、校验、引用查询、格式化和安全写回。
- `godot/scripts/core/` 负责引擎无关规则与运行时逻辑，包括 simulation、移动、交互、战斗、经济、任务、对话、AI、视野和大地图。
- `godot/scripts/app/` 负责 Godot app 装配、headless runner、游戏入口和 player interaction controller。
- `godot/scripts/world/` 负责地图快照、场景生成、空间表现、雾战和 tile / object 渲染。
- `godot/scripts/ui/` 负责 HUD、背包、任务、对话、交易、容器等 UI snapshot、controller 和面板。
- `godot/scripts/tools/` 负责 Godot headless 校验、内容 CLI、smoke 和复核脚本。
- `godot/addons/cdc_game_editor/` 负责 Godot editor 插件、handoff、content browser、map preview 和编辑 dock。

核心规则、状态计算、AI、寻路、战斗等逻辑必须继续放在 `godot/scripts/core/` 或 Godot 运行时装配层，不放在 UI、表现层或编辑器前端。编辑器依赖 Godot 数据层和核心层，但不反向成为 schema 权威。

## 内容迁移策略

当前策略是继续让 Godot 原位读取 `data/`：

- 高变动策划内容继续保留 JSON。
- Godot 数据层负责 loader、validator、reference index、format 和 edit service。
- 若未来需要 `.tres` / `.res` / `.tscn` 缓存或镜像，必须遵守“生成物可删、源仍唯一”的规则，不能长期双写两套权威 schema。

已覆盖内容域：

- ai
- appearance
- characters
- dialogues
- items
- json
- maps
- overworld
- quests
- recipes
- settlements
- shops
- skill_trees
- skills
- world_tiles

## 工具入口

当前 agent 主路径全部走 Godot：

```powershell
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario All
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01
```

手动运行入口：

```powershell
.\run_godot_game.bat
.\run_godot_editor.bat
.\run_godot_validate.bat
```

底层 Godot 命令：

```powershell
D:\godot\godot.cmd --path godot
D:\godot\godot.cmd --editor --path godot
D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/validate_all.gd
```

## 验证记录

2026-05-28 已完成以下验证：

- `cmd /c run_godot_validate.bat`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed`
- `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario All`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All`

Godot editor smoke 覆盖：

- editor handoff
- content browser
- map preview
- content edit
- map edit

Godot game smoke 覆盖：

- headless new game / world
- runtime bootstrap
- content CLI / edit
- map edit / preview
- fog shader
- world / scene
- overworld
- movement
- vision
- AI
- interaction / player interaction
- UI
- dialogue
- inventory / container / journal / trade
- quest
- combat
- progression
- equipment
- crafting
- save

## 完成定义

当前迁移完成状态满足：

- 默认运行时和工具链只使用 Godot 4.6.3 + GDScript。
- 当前树中不再保留旧运行时 workspace、旧启动脚本或旧专用验证脚本。
- agent workflow、Codex Run action、根启动脚本和清理脚本均指向 Godot。
- 内容加载、校验、摘要、引用、格式化和安全写回均由 Godot 工具链提供。
- editor handoff、content browser、map preview、content edit、map edit 均有 Godot headless smoke。
- game runtime 的新游戏、世界生成、交互、UI、任务、战斗、制作、存档均有 Godot headless smoke。

后续新功能应直接进入 Godot 数据层、核心层、场景层、UI 层或 editor 插件，不再新增并行旧栈实现。
