# Godot 4.6.3 迁移盘点、架构设计与阶段计划

## 目标

将仓库主线迁移到 `Godot 4.6.3 + GDScript`，最终脱离所有 Bevy 和 Rust。第一阶段的交付物不是删除旧实现，而是把旧边界、目标架构、内容策略、验证方式和阶段提交计划写清楚，确保后续迁移可以按模块推进、按门禁验收。

当前仓库已经推进到 Godot 主线状态；本文件同时记录第一阶段盘点结论和当前完成状态，避免后续继续以旧 Bevy / Rust 目录、脚本或工作流作为默认入口。

## 证据来源

当前状态以工作树为准，历史 Bevy / Rust 边界以 Git 历史只读盘点为补充证据。

- 当前树 `rg --files -g "*.rs" -g "Cargo.toml" -g "Cargo.lock" -g "*.wgsl" -g "*.ron"` 结果为 0，说明主线已不含 Rust / Bevy 源文件和 shader。
- Git 历史中存在 `legacy/bevy/rust/**`、`tools/tauri_editor/**`、`tools/narrative_lab/**`、旧 `addons/**` 和旧 workflow 文档，可用于回溯旧实现边界。
- 当前 Godot 工程入口是 `godot/project.godot`，Godot 命令行入口固定为 `D:\godot\godot.cmd`。
- 当前根启动脚本是 `run_godot_game.bat`、`run_godot_editor.bat`、`run_godot_validate.bat`。
- 当前 agent 标准入口是 `tools/agent/*.ps1`，全部调用 Godot 工具链。

已验证 Godot 版本：

```text
4.6.3.stable.official.7d41c59c4
```

## 旧边界盘点

### 数据与内容边界

旧实现的数据权威主要是仓库根目录 `data/` 下的 JSON。历史 Rust 工具和 Bevy viewer/editor 读取这些 JSON 后再构建运行时状态、地图静态世界、编辑器表单和预览。

当前结论：

- `data/` 仍是非地图内容权威输入源，包括 `items`、`recipes`、`characters`、`dialogues`、`quests`、`skills`、`skill_trees`、`settlements`、`shops`、`overworld`、`ai`、`appearance`、`world_tiles` 和通用 `json`。
- `godot/scenes/maps/*.tscn` 是地图布局、入口点和地图对象的当前权威输入源。
- `data/maps/*.json` 只作为迁移期兼容备份，不再作为新地图开发主入口。
- `assets/` 保留为源资产目录；Godot 可直接导入/引用的运行时资产位于 `godot/assets/`。
- 3D 正式资产遵守 `.gltf + .bin + 外部贴图`，详见 `docs/3d_asset_format_policy.md`。

### 规则与运行时边界

历史 Rust 规则主要分布在：

- `legacy/bevy/rust/crates/game_core/src/**`: actor、grid、pathfinding、economy、building、GOAP、progression、quest、dialogue、simulation 等引擎无关规则。
- `legacy/bevy/rust/crates/game_bevy/src/**`: Bevy 资源装配、世界渲染、静态地图、tile world、NPC life、mesh picking、preview、asset paths。
- `legacy/bevy/rust/apps/bevy_debug_viewer/src/**`: 可玩调试 viewer、输入、相机、game UI、info panels、render、simulation bridge、runtime state。
- `legacy/bevy/rust/apps/bevy_server/src/**`: server / protocol / projection / startup / reporting。

当前 Godot 对应边界：

- `godot/scripts/core/`: 引擎无关规则和运行时逻辑。
- `godot/scripts/world/`: 地图快照、地图场景加载、空间表现、雾战和 object / tile 渲染。
- `godot/scripts/app/`: Godot app 装配、启动、保存、headless runner 和 player interaction controller。
- `godot/scripts/ui/`: HUD、背包、任务、对话、交易、容器等 UI snapshot 与 controller。

核心原则：

- 状态计算、AI、寻路、战斗、经济、任务、对话、视野等规则不得写回 UI、editor dock 或纯表现层。
- 可复用纯规则优先实现为 Godot 引擎无关的 `RefCounted` 模块。
- 场景层只做空间表现、输入转接和运行时装配。

### 编辑器边界

历史编辑器实现包括：

- `legacy/bevy/rust/apps/bevy_*_editor/src/**`: item、recipe、character、dialogue、quest、skill、map、gltf viewer 等 Bevy editor。
- `tools/tauri_editor/**`: Tauri + React 数据编辑器、地图编辑器、图编辑器、AI 面板。
- `tools/narrative_lab/**`: Tauri + React 叙事工作台。
- 旧根目录 `addons/**`: 早期 Godot editor 插件、procedural builder、gameplay tags 等残留实现。

当前结论：

- 当前 Godot editor 插件只以 `godot/addons/cdc_game_editor/` 为准。
- 根目录 `addons/` 若只包含旧备份或残留文件，不作为当前 Godot 插件来源。
- 内容浏览、handoff、map review、表单编辑等 editor 能力必须复用 `godot/scripts/data/` 的 loader、validator、reference index 和 edit service。
- 内容编辑器保持独立工具形态，不把编辑能力塞回玩家运行时。

### 工具脚本与工作流边界

历史工具包括：

- `legacy/bevy/rust/apps/content_tools/src/**`: locate、summarize、references、format、diff-summary、changed 等内容 CLI。
- `tools/agent/test-bevy-game.ps1`、`review-map-visual.ps1`、`open-editor.ps1` 等旧 agent 入口。
- 旧 Tauri editor / narrative lab 的 npm、Vitest、Playwright、Tauri smoke。

当前 Godot 工具入口：

- `tools/agent/godot-content.ps1`: 内容定位、摘要、引用、校验、格式化、diff-summary。
- `tools/agent/test-godot-game.ps1`: Godot runtime / game headless smoke。
- `tools/agent/test-godot-editor.ps1`: Godot editor 插件和编辑服务 headless smoke。
- `tools/agent/open-godot-editor.ps1`: 打开或复用 Godot editor 并写入 handoff 请求。
- `tools/agent/review-godot-map-visual.ps1`: 地图空间结果复核入口。

## 目标 Godot 工程架构

### 目录职责

- `godot/project.godot`: Godot 工程入口。
- `godot/scenes/boot/`: 启动场景与主菜单。
- `godot/scenes/game/`: 玩家游戏根场景。
- `godot/scenes/maps/`: 地图 `.tscn`，承载 map id、尺寸、入口点、地图对象、footprint、props 和视觉子节点。
- `godot/scenes/ui/`: HUD、背包、任务、对话、交易、容器等 UI 场景。
- `godot/assets/`: Godot 可导入资源，包括 glTF、shader、icon 和导入设置。
- `godot/scripts/data/`: 内容路径、JSON 加载、registry、校验、引用查询、格式化和安全写回。
- `godot/scripts/core/`: 引擎无关公共规则与运行时逻辑。
- `godot/scripts/app/`: app 装配、启动、保存、headless runner 和 player interaction controller。
- `godot/scripts/world/`: 地图定义加载、拓扑构建、场景渲染、雾战和空间表现。
- `godot/scripts/ui/`: UI snapshot、controller 和面板逻辑。
- `godot/scripts/tools/`: Godot headless 校验、内容 CLI、smoke 和复核脚本。
- `godot/addons/cdc_game_editor/`: editor 插件、handoff、content browser、map review 和编辑 dock。
- `data/`: 非地图内容权威输入源；`data/maps` 为兼容备份。
- `tools/agent/`: repo-local agent workflow 标准入口。

### 资源类型

- 地图布局：`godot/scenes/maps/*.tscn`。
- 非地图策划内容：`data/**/*.json`。
- 3D 资产：`godot/assets/**/*.gltf` 搭配 `.bin` 和 `.gltf.import`。
- Shader：`godot/assets/shaders/*.gdshader`。
- UI：`godot/scenes/ui/*.tscn` + `godot/scripts/ui/**`。
- Editor 插件：`godot/addons/cdc_game_editor/plugin.cfg` + `*.gd`。
- 临时缓存、导入库和 session：`godot/.godot/`、`.local/`、`tmp/`，不作为权威输入。

### 场景结构

- `boot.tscn` / `main_menu.tscn`: 只负责启动和进入 game root。
- `game_root.tscn`: 挂载 `game_app.gd`，装配 registry、simulation、world renderer、fog overlay 和 UI panels。
- `maps/*.tscn`: 根节点使用 `MapSceneRoot`，子节点分为入口点和对象；对象使用 `MapObjectNode`，视觉资产放入 `Visuals` 子树。
- `ui/*.tscn`: 控制只显示 snapshot，不直接计算核心规则。
- editor dock 通过 `SubViewport` 做地图预览，不成为地图 schema 权威。

### GDScript 模块划分

| 旧 Rust / Bevy 能力 | Godot 目标模块 |
| --- | --- |
| `game_core` actor / registry | `godot/scripts/core/actor/` |
| grid、pathfinding、movement | `godot/scripts/core/grid/`、`godot/scripts/core/movement/` |
| combat、equipment、inventory、shop、container | `godot/scripts/core/combat/`、`godot/scripts/core/economy/` |
| dialogue、quest、progression | `godot/scripts/core/dialogue/`、`godot/scripts/core/quests/`、`godot/scripts/core/progression/` |
| GOAP / NPC life / settlement AI | `godot/scripts/core/ai/` |
| vision / fog rules | `godot/scripts/core/vision/`、`godot/scripts/world/fog_overlay_controller.gd` |
| static world / map scene / tile world | `godot/scripts/world/` + `godot/scenes/maps/` |
| Bevy debug viewer runtime bridge | `godot/scripts/app/` + `godot/scripts/world/` |
| Bevy game UI panels | `godot/scripts/ui/` + `godot/scenes/ui/` |
| content_tools CLI | `godot/scripts/tools/content_cli*.gd` + `tools/agent/godot-content.ps1` |
| Bevy / Tauri editors | `godot/addons/cdc_game_editor/` + `godot/scripts/data/` |

## 内容迁移策略

1. 地图先进入 Godot scene 工作流。
   - `godot/scenes/maps/*.tscn` 是主入口。
   - `data/maps/*.json` 保留兼容备份，不再作为新地图开发入口。
   - 后续地图布局、入口点、对象、footprint、rotation、props 和视觉资产都按 Godot scene 方式维护。

2. 非地图内容继续使用 JSON。
   - 高变动策划内容保留在 `data/`，避免过早引入 `.tres` / `.res` 双写 schema。
   - Godot 数据层负责加载、校验、引用查询、摘要、格式化和安全写回。

3. 资产路径进入 Godot project。
   - `data/world_tiles/*.json` 继续描述 tile / prop prototype。
   - Godot 运行时和地图场景使用 `godot/assets/**/*.gltf`。
   - 根目录 `assets/` 可作为源资产池；Godot 可运行资源必须能在 `res://assets/...` 下解析。

4. 不保留双实现。
   - 同一长期能力只能有一个权威实现。
   - 迁移期可存在兼容备份，但不能继续新增 Bevy / Rust 路径。
   - `.tres` / `.res` 缓存若未来引入，必须是可删生成物，不能成为第二套长期 schema。

## 验证方式

基础验证：

```powershell
cmd /c run_godot_validate.bat
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed
```

Runtime 验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All
```

Editor 验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario All
```

地图空间复核：

```powershell
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01
```

手动入口：

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

## 阶段提交计划

### P0 盘点与设计

交付物：

- 本文件。
- `AGENTS.md` 中的当前 Godot 工作方式。
- `tools/agent/README.md` 和 `docs/agent-workflows/*.md` 的 Godot 工具入口说明。

验收：

- 旧 Rust/Bevy 数据、规则、运行时、编辑器、工具脚本和文档边界有明确去向。
- Godot 目录、资源类型、场景结构、GDScript 模块边界、内容策略、验证方式和阶段计划完整。
- 不在该阶段强制删除旧实现。

### P1 数据层与核心规则迁移

交付物：

- `godot/scripts/data/` loader、registry、validator、reference index、edit service。
- `godot/scripts/core/` actor、grid、movement、vision、AI、combat、economy、dialogue、quest、progression、simulation。

验收：

- `run_godot_validate.bat` 通过。
- runtime / movement / vision / AI / combat / quest / crafting / save 等 smoke 通过。
- 新规则不写进 UI、editor dock 或表现层。

### P2 地图与资产迁移

交付物：

- `godot/scenes/maps/*.tscn`。
- `godot/scripts/world/map_scene_*.gd`、`map_builder.gd`、`world_snapshot_builder.gd`、`world_scene_renderer.gd`。
- `godot/assets/world_tiles/**`、`godot/assets/container_placeholders/**`。

验收：

- 地图从 `.tscn` 加载，`data/maps` 只作为兼容备份。
- 运行时和 editor preview 不再显示旧占位方块作为主要视觉。
- `World`、`Scene`、`MapReview` smoke 通过。

### P3 玩家运行时与 UI 闭环

交付物：

- `godot/scenes/game/game_root.tscn`、`godot/scripts/app/**`。
- `godot/scenes/ui/*.tscn`、`godot/scripts/ui/**`。

验收：

- 新游戏、地图切换、交互、背包、容器、交易、任务、对话、战斗、制作、装备、存档 smoke 通过。
- 玩家运行时不承载内容编辑 UI。

### P4 Editor 与 agent 工具迁移

交付物：

- `godot/addons/cdc_game_editor/**`。
- `godot/scripts/tools/**`。
- `tools/agent/*.ps1`。
- `docs/agent-workflows/*.md`。

验收：

- Godot editor handoff、content browser、map review、content edit smoke 通过。
- agent 内容定位、摘要、引用、校验、格式化和 diff-summary 全部走 Godot。
- 新增 agent 脚本必须同步补 help、`tools/agent/README.md` 和对应 workflow 文档。

### P5 旧栈下线

交付物：

- 根启动脚本只保留 Godot 入口。
- 默认验证只走 Godot。
- Bevy / Rust / Tauri editor / narrative lab 不再作为主线运行或验证依赖。

验收：

- 当前树不含 `.rs`、`Cargo.toml`、`Cargo.lock`、Bevy 专用 shader 或旧 Bevy runner。
- 旧实现只通过 Git 历史追溯，或被明确标记为非当前权威的兼容备份。

### P6 完成态验收

完成定义：

- 默认运行时和工具链只使用 `Godot 4.6.3 + GDScript`。
- 当前可运行、可验证、可编辑的工程只依赖 `godot/`、`data/`、`tools/agent/` 和根 Godot 启动脚本。
- 地图主来源为 `godot/scenes/maps/*.tscn`。
- 非地图内容主来源为 `data/` JSON。
- 内容加载、校验、摘要、引用、格式化和安全写回由 Godot 数据层与工具链提供。
- editor handoff、content browser、map review、content edit 均有 Godot headless smoke。
- game runtime 的新游戏、世界生成、交互、UI、任务、战斗、制作、存档均有 Godot headless smoke。

## 当前完成状态

当前仓库已处于 P6 主线完成态：

- `godot/project.godot` 存在并作为工程入口。
- 当前树中没有 Rust / Cargo / Bevy 源文件。
- 根运行入口是 `run_godot_game.bat`、`run_godot_editor.bat`、`run_godot_validate.bat`。
- `tools/agent` 默认走 Godot。
- 地图场景已位于 `godot/scenes/maps/*.tscn`。
- 非地图内容仍由 `data/` JSON 承载。
- Godot runtime 和 editor smoke 已覆盖当前可玩与可编辑闭环。

后续新功能应直接进入 Godot 数据层、核心层、场景层、UI 层或 editor 插件，不再新增并行旧栈实现。

## 已知后续清理项

- 根目录 `assets/` 与 `godot/assets/` 存在源资产池和 Godot 导入资产的双目录关系；新增正式运行时资源必须确保 `res://assets/...` 可解析。
- `data/maps/*.json` 作为兼容备份保留；新地图开发不得继续把它作为主入口。
- Godot headless smoke 在通过后可能打印 RID/resource leak 退出警告；这不等于 smoke 失败，但后续可以单独优化 headless teardown。
- 根目录旧 `addons/` 若继续保留，必须持续标记为非当前 Godot 插件来源，避免误用。
