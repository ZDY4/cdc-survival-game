# Godot 4.6.3 全量迁移盘点与架构计划

## 文档目的

本文件是“从 Rust/Bevy 全量迁移到 Godot 4.6.3 + GDScript”的第一阶段执行计划。

当前阶段只做迁移盘点和目标架构设计，不删除旧实现，不把 Godot 与 Rust/Bevy 做长期双写，不把编辑器重新作为权威数据来源。旧 Rust/Bevy 代码在迁移期间只作为行为基线、内容校验基线和回归对照。

Godot 已安装在 `D:/godot`，命令行入口固定使用：

```powershell
D:\godot\godot.cmd
```

已验证版本：

```text
4.6.3.stable.official.7d41c59c4
```

## 迁移原则

- 最终工程只保留 Godot 4.6.3 + GDScript 作为运行时与工具链主体，彻底脱离 Bevy 和 Rust。
- 迁移阶段先复刻权威边界，再复刻行为；不要逐文件机械翻译 Rust。
- 内容数据继续以仓库 `data/` 中的 JSON 为迁移输入，直到 Godot 侧资源格式和校验稳定后再决定是否转换为 `.tres` / `.res`。
- 核心规则、状态计算、AI、寻路、战斗、任务、经济和交互仍然放在引擎表现层之外，只是实现语言从 Rust 迁到 GDScript。
- Godot editor 插件和专用工具只负责内容生产体验，不成为 schema 权威。
- 每个迁移阶段都必须有可运行验证命令和可回归的最小场景。

## 当前仓库边界盘点

### Rust workspace

`rust/Cargo.toml` 当前 workspace 包含 16 个成员：

| 当前模块 | 规模 | 当前职责 | Godot 目标归宿 |
| --- | ---: | --- | --- |
| `rust/crates/game_data` | 43 文件，约 20765 行 | 共享内容 schema、加载、引用校验、编辑服务 | `godot/scripts/data/` 与 `godot/scripts/content/` |
| `rust/crates/game_core` | 86 文件，约 26507 行 | 引擎无关规则、模拟、战斗、经济、任务、移动、AI、视野 | `godot/scripts/core/` |
| `rust/crates/game_bevy` | 43 文件，约 18002 行 | Bevy runtime 装配、内容加载资源、世界渲染、UI snapshot、NPC life 集成 | 拆到 `godot/scripts/app/`、`godot/scripts/world/`、`godot/scripts/ui/` |
| `rust/crates/game_editor` | 18 文件，约 2719 行 | Bevy editor 共用壳、预览、handoff、模型工具 | `godot/addons/cdc_game_editor/` 与 `godot/tools/` |
| `rust/crates/game_protocol` | 2 文件，约 516 行 | headless server IPC 消息 | 先废弃为迁移参考，若未来需要外部进程再用 Godot JSON/RPC 重建 |
| `rust/apps/bevy_server` | 12 文件，约 3597 行 | headless Bevy runtime 入口、协议分发、报告 | `godot/scripts/app/headless_runner.gd` 或 CLI tool script |
| `rust/apps/bevy_debug_viewer` | 123 文件，约 39438 行 | 当前主客户端、调试 viewer、游戏 UI、输入、渲染、存档、性能面板 | `godot/scenes/game/`、`godot/scripts/app/`、`godot/scripts/ui/`、`godot/scripts/debug/` |
| `rust/apps/bevy_map_editor` | 13 文件，约 3403 行 | 地图专用编辑器 | `godot/addons/cdc_game_editor/editors/map_editor/` |
| `rust/apps/bevy_character_editor` | 18 文件，约 3432 行 | 角色和 AI 预览编辑器 | `godot/addons/cdc_game_editor/editors/character_editor/` |
| `rust/apps/bevy_gltf_viewer` | 9 文件，约 2273 行 | glTF / bbmodel 预览与 socket 编辑 | `godot/tools/model_viewer/` 或 editor dock |
| `rust/apps/bevy_item_editor` | 9 文件，约 1436 行 | 物品编辑器 | `godot/addons/cdc_game_editor/editors/item_editor/` |
| `rust/apps/bevy_recipe_editor` | 9 文件，约 1196 行 | 配方编辑器 | `godot/addons/cdc_game_editor/editors/recipe_editor/` |
| `rust/apps/bevy_dialogue_editor` | 9 文件，约 1134 行 | 对话图编辑器 | `godot/addons/cdc_game_editor/editors/dialogue_editor/` |
| `rust/apps/bevy_quest_editor` | 10 文件，约 1085 行 | 任务图编辑器 | `godot/addons/cdc_game_editor/editors/quest_editor/` |
| `rust/apps/bevy_skill_editor` | 9 文件，约 1187 行 | 技能树编辑器 | `godot/addons/cdc_game_editor/editors/skill_editor/` |
| `rust/apps/content_tools` | 8 文件，约 1408 行 | CLI 内容定位、摘要、引用、校验、格式化 | `godot/tools/content_cli/`，用 Godot headless 脚本替代 |

### 内容数据

`data/` 是迁移输入的核心资产：

| 目录 | 文件数 | 说明 |
| --- | ---: | --- |
| `data/items` | 126 | 物品定义，当前体量最大 |
| `data/json` | 65 | 较早的共享规则/效果/平衡数据 |
| `data/recipes` | 30 | 配方 |
| `data/dialogues` | 22 | 对话图 |
| `data/skills` | 13 | 技能定义 |
| `data/maps` | 12 | 地图、对象、触发器、AI spawn |
| `data/characters` | 11 | 角色定义 |
| `data/ai` | 8 | AI 行为、模块、profile |
| `data/world_tiles` | 4 | tile prototype catalog |
| `data/quests` | 4 | 任务图 |
| `data/skill_trees` | 3 | 技能树 |
| `data/appearance` | 1 | 角色外观 |
| `data/bootstrap` | 1 | 新游戏启动配置 |
| `data/overworld` | 1 | 大地图 |
| `data/settlements` | 1 | 据点、smart object、route |
| `data/shops` | 1 | 商店 |

第一阶段不移动这些 JSON。Godot 侧先实现只读加载和校验，后续再按稳定程度转换：

- 高变动策划内容：短期继续 JSON。
- 需要 Godot inspector 友好编辑的资源：中期生成 `.tres` 镜像，但只在迁移完成后切换为权威。
- 大型地图与 tile：先 JSON 驱动生成场景，后续可缓存为 `.tscn` 或 PackedScene。

### 视觉与资源

当前 `assets/` 主要包含：

| 目录 | 文件数 | 迁移处理 |
| --- | ---: | --- |
| `assets/world_tiles` | 62 | glTF/bin tile 资产，导入 Godot 后生成 tile prototype scene |
| `assets/bevy_preview` | 20 | 角色和装备 placeholder，先作为 Godot placeholder 复用 |
| `assets/container_placeholders` | 3 | 容器模型，直接导入 |
| `assets/fonts` | 1 | Noto Sans CJK 字体，迁到 Godot UI theme |
| `assets/shaders` | 1 | WGSL 雾战 shader，需用 Godot shader 重写 |
| `assets/generated` | 0 | 保留为生成资产输出候选 |

仓库已有 `addons/` 和 `ui/` 目录，但目前只发现 `addons/cdc_game_editor/editors/item_editor/item_editor.gd.bak` 一个旧 Godot 备份文件。该文件存在中文编码损坏和旧 schema 倾向，只能作为历史思路参考，不作为迁移权威。

### 工具脚本与文档

当前 agent 标准入口在 `tools/agent/`：

- `open-editor.ps1`: 打开或复用 Bevy editor 并定位内容。
- `review-map-visual.ps1`: 地图摘要、引用、校验和 Bevy map editor 视觉复核。
- `test-bevy-game.ps1`: Bevy game smoke 测试。

当前内容 CLI 在 `rust/apps/content_tools`：

- `locate`
- `validate`
- `summarize`
- `references`
- `format`
- `diff-summary`

迁移期间先保留这些工具作为旧基线。Godot 侧达到等价能力后，新增 `tools/agent/open-godot-editor.ps1`、`tools/agent/review-godot-map-visual.ps1`、`tools/agent/test-godot-game.ps1`，并同步更新 `tools/agent/README.md` 与 `docs/agent-workflows/*.md`。新增脚本必须保留 PowerShell comment-based help。

## 目标 Godot 工程结构

Godot 工程放在仓库根目录的新目录 `godot/`，避免与现有 `assets/`、`data/`、`rust/` 在迁移期互相污染。

```text
godot/
  project.godot
  icon.svg
  addons/
    cdc_game_editor/
      plugin.cfg
      plugin.gd
      docks/
      editors/
        item_editor/
        recipe_editor/
        character_editor/
        map_editor/
        dialogue_editor/
        quest_editor/
        skill_editor/
  assets/
    fonts/
    models/
    world_tiles/
    placeholders/
    materials/
    shaders/
  scenes/
    boot/
      boot.tscn
      main_menu.tscn
    game/
      game_root.tscn
      world_view.tscn
      actor.tscn
      interaction_prompt.tscn
    ui/
      hud.tscn
      inventory_panel.tscn
      crafting_panel.tscn
      trade_panel.tscn
      dialogue_panel.tscn
      journal_panel.tscn
      map_panel.tscn
      debug_panel.tscn
    editor_preview/
      model_preview.tscn
      map_preview.tscn
  scripts/
    app/
      boot.gd
      game_app.gd
      runtime_bootstrap.gd
      save_service.gd
      headless_runner.gd
    data/
      content_paths.gd
      json_loader.gd
      content_registry.gd
      validation_result.gd
      definitions/
    core/
      simulation/
      runtime/
      grid/
      movement/
      interactions/
      combat/
      economy/
      crafting/
      progression/
      quests/
      dialogue/
      ai/
      vision/
      overworld/
      building/
    world/
      map_builder.gd
      tile_world.gd
      static_world.gd
      actor_spawner.gd
      world_renderer.gd
      fog_of_war.gd
    ui/
      snapshots/
      controllers/
      widgets/
      theme/
    debug/
      console.gd
      profiler.gd
      debug_overlay.gd
    tools/
      content_cli.gd
      import_data.gd
      validate_all.gd
  tests/
    unit/
    integration/
    fixtures/
  exported/
```

迁移期 `godot/scripts/data/content_paths.gd` 读取仓库根目录的 `data/`，`godot/assets/` 则接收 Godot import 后的资源副本或软迁移清单。最终脱离 Rust/Bevy 后，再决定是否把根目录 `assets/` 合并进 `godot/assets/`。

## GDScript 模块划分

### `scripts/data`

对齐 `game_data`，负责：

- JSON 文件加载、路径解析、错误上下文。
- 定义对象：角色、物品、效果、技能、技能树、配方、任务、对话、对话规则、地图、overworld、world tile、据点、商店、AI 模块。
- 内容库：按 id 索引、重复 id 检查、引用查询。
- 校验器：schema 必填项、枚举值、跨内容引用、地图出口覆盖、AI 内容完整性。
- 编辑服务：item / recipe / character / map 的最小读写，以及 quest / skill / skill_tree 的安全元数据写回、格式化、诊断。

建议用 `RefCounted` 数据类表达定义对象，用 `class_name` 暴露稳定 API；复杂嵌套字段先保留 `Dictionary`，等行为稳定后再逐步收窄类型。

### `scripts/core`

对齐 `game_core`，负责：

- `simulation`: actor 注册、命令、事件、snapshot、状态持久化。
- `runtime`: 对外 facade，新游戏、tick、命令执行、事件收集。
- `grid`: 坐标、阻挡、寻路、范围查询。
- `movement`: 自动移动、交互意图、地图切换。
- `interactions`: door / pickup / container / talk / attack / wait / scene_transition。
- `combat`: 目标查询、命中、伤害、死亡、掉落、战斗 AI 意图。
- `economy`: 背包、装备、交易、容器、商店状态。
- `crafting`: 配方检查、材料消耗、产出。
- `progression`: 技能、经验、等级、属性。
- `quests`: 任务图状态、条件、奖励、推进事件。
- `dialogue`: 对话起点、节点推进、规则选择、动作产出。
- `ai`: GOAP / utility / schedule / need / offline action。
- `vision`: 视野、雾战数据、可见对象快照。
- `overworld`: 大地图路径、地点解锁、地点进入。
- `building`: 建筑布局和几何生成。

核心层不直接依赖 scene tree、Control 节点或编辑器 API。需要时间、随机数和日志时通过可替换 service 注入，便于 headless 测试。

### `scripts/world`

对齐 `game_bevy::static_world`、`world_render`、`tile_world` 和 debug viewer render：

- 从 map / overworld 定义生成 Godot scene tree。
- 管理 grid 到 3D 坐标转换、tile prototype 实例化、对象 footprint、门和触发器表现。
- 将 `SimulationSnapshot` 映射为 actor、容器、掉落物、交互提示和雾战表现。
- Godot Shader 重写 `assets/shaders/fog_of_war_post_process.wgsl`。

### `scripts/ui`

对齐 `game_bevy::ui` 和 `bevy_debug_viewer/src/game_ui`：

- 保留 snapshot 思路：核心层产出 UI 只读快照，UI controller 只发命令。
- 面板包括主菜单、HUD、背包、技能、制作、交易、容器、对话、日志、地图、设置。
- Debug 面板拆到 `scripts/debug`，玩家默认路径不暴露调试噪音。

### `addons/cdc_game_editor`

对齐当前多个 Bevy editor app：

- 第一批只做内容浏览、定位、校验结果展示和地图/模型预览。
- 第二批再补 item / recipe / character / map 的编辑能力，以及 quest / skill / skill_tree 的元数据表单。
- 第三批补 graph 类 editor：dialogue / quest flow / skill tree links。
- 所有保存逻辑调用 `scripts/data` 编辑服务，不在插件中重复 schema。

## 数据迁移策略

### 阶段 A：JSON 原位读取

Godot 直接读取仓库根目录 `data/`：

- 优点：不改变现有内容，不引入双写。
- 验证：Godot `validate_all` 与 Rust `content_tools validate changed` 输出对照。
- 交付：所有内容库能加载，关键引用能校验，错误能定位到文件和字段。

### 阶段 B：行为端口

按当前 playable build 需要迁移核心规则：

1. 新游戏启动：`data/bootstrap/new_game_default.json`。
2. 地图加载：`survivor_outpost_01`、`survivor_outpost_01_perimeter`、`hospital`、`factory`。
3. 玩家、老王、陈医生和基础 zombie。
4. 移动、交互、pickup、container、talk、attack、scene_transition。
5. 背包、装备、制作、交易、任务、对话。
6. 存档和继续游戏。

### 阶段 C：Godot 资源化

当加载和行为稳定后再决定资源化粒度：

- `.tres`: effect、item category、skill、recipe、AI profile 等 inspector 友好数据。
- `.tscn`: 地图缓存、tile prototype、角色预制体、UI 面板。
- `.res`: 大型索引、缓存的导航/遮挡/可视化数据。

在切换权威前，禁止同时维护 JSON 和 `.tres` 的长期双写。若需要生成镜像，必须有“生成物可删、源仍唯一”的规则。

## 运行时迁移策略

### MVP 场景

第一版 Godot runtime smoke 只追求等价闭环：

- 从主菜单新游戏进入 `survivor_outpost_01`。
- 玩家、商人老王、陈医生生成在启动配置指定位置。
- 能显示地图基础地面、阻挡、对象、交互目标。
- 能移动、打开交互菜单、拾取、对话、攻击、切图。
- UI 能显示世界状态、背包、任务、对话、交易/容器最小路径。

### 与 Bevy 的对照基线

迁移中保留以下旧命令作为对照：

```powershell
pwsh -NoProfile -File tools/agent/test-bevy-game.ps1
pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map survivor_outpost_01 -NoOpenEditor
Push-Location rust; cargo run -q -p content_tools -- validate changed; Pop-Location
```

Godot 侧逐步建立等价命令：

```powershell
.\run_godot_game.bat
.\run_godot_editor.bat
.\run_godot_validate.bat
D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/validate_all.gd
D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/content_cli.gd validate changed
D:\godot\godot.cmd --headless --path godot --script res://scripts/app/headless_runner.gd --scenario new_game_smoke
D:\godot\godot.cmd --path godot
```

## 编辑器迁移策略

编辑器不作为第一批阻塞项。推荐顺序：

1. `content_cli`: 先替代 `content_tools` 的 locate / validate / summarize / references / format。
2. `map_preview`: 先替代 `review-map-visual.ps1` 的空间复核能力。
3. `item_editor`、`recipe_editor`、`character_editor`: 表单型内容先迁。
4. `dialogue_editor`、`quest_editor`、`skill_editor`: 图编辑器后迁。
5. `model_viewer`: 迁移 glTF / socket / placeholder 预览。

当前 `addons/cdc_game_editor/editors/item_editor/item_editor.gd.bak` 只作为历史参考，不直接恢复。新插件必须重新绑定当前 `data/items/*.json` 与 Godot 侧 content service。

## 工具脚本迁移策略

新增 Godot 工具脚本时遵循现有 agent 规则：

- 所有脚本使用 PowerShell 7。
- 先补脚本自身 comment-based help。
- 同步补 `tools/agent/README.md`。
- 同步补 `docs/agent-workflows/*.md`。
- 旧 Bevy 脚本保留到 Godot 等价脚本通过验证后再移除。

计划新增：

| 新脚本 | 替代对象 | 目标 |
| --- | --- | --- |
| `tools/agent/test-godot-game.ps1` | `test-bevy-game.ps1` | 运行 Godot headless / smoke 场景 |
| `tools/agent/open-godot-editor.ps1` | `open-editor.ps1` | 打开 Godot editor 并写入 handoff |
| `tools/agent/review-godot-map-visual.ps1` | `review-map-visual.ps1` | 地图校验、摘要、视觉预览 |
| `tools/agent/godot-content.ps1` | `content_tools` | 包装 Godot content CLI |

## 验证方式

### 文档阶段

- `D:\godot\godot.cmd --version`
- `git diff -- docs/plans/10_godot_migration_architecture.md`

### Godot 工程骨架阶段

- `D:\godot\godot.cmd --headless --path godot --quit`
- `D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/validate_all.gd`

### 数据加载阶段

- 加载全部 `data/` 内容库。
- 对照 Rust content validation 的成功/失败集合。
- 输出带文件路径、内容 id、字段路径、失败原因的诊断。

### 规则迁移阶段

- GDScript 单元测试覆盖 grid、movement、interaction、combat、economy、quest、dialogue。
- Godot headless scenario 覆盖新游戏、拾取、对话、攻击、切图、存档。
- 与 Rust snapshot 对照关键状态字段：actor id、位置、背包、任务状态、当前地图、事件序列。

### 表现迁移阶段

- Godot editor / runtime 手动 smoke。
- 地图视觉复核：tile、墙、门、容器、pickup、trigger、AI spawn 坐标。
- UI 无 debug 噪音默认暴露，玩家路径可完成首个 10-20 分钟闭环。

## 阶段提交计划

### Commit 1：迁移盘点与架构计划

交付：

- 本文件。
- 不改旧实现。

验证：

- `D:\godot\godot.cmd --version`
- 文档 diff 复核。

### Commit 2：Godot 工程骨架

交付：

- `godot/project.godot`
- boot scene、autoload/service 空壳。
- 基础目录和 README。

验证：

- Godot headless 能打开工程。

### Commit 3：内容加载和校验骨架

交付：

- JSON loader。
- content registry。
- item / character / map / recipe 的首批定义加载。
- `validate_all.gd`。

验证：

- Godot 能加载关键内容。
- 与 Rust `content_tools validate changed` 对照。

### Commit 4：核心 runtime 最小端口

交付：

- grid、actor registry、simulation command/event、new game seed。
- 可 headless 跑 `new_game_smoke`。

验证：

- 玩家、老王、陈医生生成。
- actor snapshot 稳定。

### Commit 5：地图场景和基础交互

交付：

- 地图生成、tile prototype 实例化、基础相机和点击/键盘输入。
- pickup / talk / scene_transition 最小交互。

验证：

- Godot 窗口能进入 outpost 并进行基础交互。

### Commit 6：玩家 UI 与首个闭环

交付：

- HUD、背包、对话、任务、交易/容器最小 UI。
- 首个任务闭环。

验证：

- 新游戏后 10-20 分钟主循环可完成。

### Commit 7：Godot 内容工具与 editor 插件第一批

交付：

- Godot content CLI。
- item / recipe / character 浏览与校验。
- map preview。
- agent 脚本文档更新。

验证：

- Godot 工具覆盖现有 agent 内容修改主路径。

### Commit 8：关闭 Bevy/Rust 依赖

前置条件：

- Godot runtime、内容工具、必要 editor 能覆盖日常开发。
- 旧 Bevy smoke 的目标在 Godot smoke 中有等价覆盖；`test-godot-game.ps1 -Scenario BevyEquivalence` 输出 `WorldInteractionMenu` 到 Godot smoke 的机器可读覆盖映射。
- 文档和 agent workflow 都已切到 Godot。
- 根目录已有 `run_godot_game.bat`、`run_godot_editor.bat`、`run_godot_validate.bat` 作为旧 `run_bevy_*` 的迁移期默认替代入口。

交付：

- 删除或归档 `rust/`、Bevy run bat、Bevy 专用脚本和旧日志路径。
- 更新 `AGENTS.md` 当前基线。

验证：

- 仓库不再需要 `cargo`、Bevy 或 Rust workspace 即可运行游戏和工具。

## 风险与处理

- 规则体量大：先迁 playable 需要的纵向切片，再迁剩余系统。
- GDScript 类型约束弱：关键定义和 runtime state 使用集中校验、清晰命名和单元测试补足。
- Godot 3D tile 性能未知：先用场景实例化跑通，再评估 MultiMesh、GridMap 或自定义 mesh 合批。
- shader 不可直接迁：WGSL 雾战需要 Godot shader 重写，并用 headless/窗口 smoke 对比可见性数据。
- 编辑器数量多：先 CLI 和 preview，后完整编辑体验。
- 旧数据 schema 可能夹带历史字段：Godot loader 先宽读严校，诊断可行动后再收紧。

## 第一阶段完成定义

本阶段完成时应满足：

- 已明确现有 Rust/Bevy 数据、规则、运行时、编辑器、工具脚本和文档边界。
- 已明确 Godot 项目目录、资源类型、场景结构、GDScript 模块划分。
- 已明确内容迁移策略、验证方式和阶段提交计划。
- 没有删除旧实现。
- 有一次只包含迁移计划文档的提交，作为后续 Godot 工程落地基线。
