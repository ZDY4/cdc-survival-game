# 地图 Tile 数据 Godot 原生资源化方案

本文定义把当前 `data/world_tiles/*.json` 改造成 Godot 原生数据资产的路线。目标不是改用 `GridMap`、`MeshLibrary` 或 2D `TileSet`，而是在保留当前 scene/node 地图架构的前提下，把地图块、建筑块、地表块和常用 prop prototype 从外部 JSON 字符串配置，迁移为可在 Godot Inspector 中编辑、可被场景直接引用、也便于 agent 文本读写的 `.tres Resource`。

## 背景

当前地图 tile 数据位于 `data/world_tiles/*.json`，由 `ContentRegistry` 加载，再通过 `AssetPathResolver` 把 `builtin:world_tile:*` 或记录内的 `source.path` 解析为 `res://assets/world_tiles/**/*.gltf`。

这套数据层可以工作，但它更像外部内容数据库：

- prototype、surface set、wall set 之间通过字符串 id 互相引用。
- 资源路径需要 resolver 二次解释，Godot Editor 无法直接在 Inspector 中暴露缺失引用。
- `tile_set` 命名容易和 Godot 原生 `TileSet` 概念混淆。
- `CDC Map Tile Palette` 需要理解 JSON schema，无法直接复用 Godot Resource 的导出字段、资源选择器和引用检查。

迁移后的目标是让地图 tile 数据成为 Godot 工程内的一等资产，同时继续支持 agent 通过文本 `.tres` 批量读写、审查和生成。

## 目标

- 使用自定义 `Resource` 表达地图 tile prototype、建筑墙组、地表组和 palette。
- 使用文本 `.tres` 作为权威资源格式，不使用二进制 `.res`。
- 让 tile prototype 直接持有 `PackedScene` 引用，减少 `source.path` 字符串和 resolver 依赖。
- 让 `CDC Map Tile Palette` 优先读取 Godot Resource，而不是直接读取 JSON。
- 保持现有 `godot/scenes/maps/*.tscn`、`MapBuilding3D/Visuals`、`MapObjectNode`、交互逻辑、存档和运行时 map definition schema 稳定。
- 迁移期间提供 JSON fallback 或一次性转换工具，避免一次提交同时重写所有地图和工具。
- 保留 agent 友好性：资源文件可 grep、可 diff、可通过 Godot headless 校验。

## 非目标

- 不把地图改成 Godot `GridMap`。
- 不生成 `.tres MeshLibrary`。
- 不接入 Godot GridMap panel。
- 不把 items、recipes、characters、quests 等全部非地图内容同步资源化。
- 不改变 gameplay API、interaction target schema、地图切换数据结构或存档字段。
- 不在本计划内重做 tile 美术资产、碰撞资产或材质系统。

## 目标资源类型

新增 Godot 自定义 Resource 脚本，建议放在：

```text
godot/scripts/world/tiles/
```

建议类型：

```gdscript
class_name WorldTilePrototype
extends Resource

@export var id: StringName
@export var display_name: String
@export_enum("building", "surface", "prop", "marker") var category: String = "building"
@export var scene: PackedScene
@export var footprint: Vector2i = Vector2i.ONE
@export var tags: PackedStringArray = []
```

```gdscript
class_name WorldWallTileSet
extends Resource

@export var id: StringName
@export var display_name: String
@export var corner: WorldTilePrototype
@export var straight: WorldTilePrototype
@export var end: WorldTilePrototype
@export var t_junction: WorldTilePrototype
@export var cross: WorldTilePrototype
@export var isolated: WorldTilePrototype
```

```gdscript
class_name WorldSurfaceTileSet
extends Resource

@export var id: StringName
@export var display_name: String
@export var flat_top: WorldTilePrototype
@export var ramp_north: WorldTilePrototype
@export var ramp_south: WorldTilePrototype
@export var ramp_east: WorldTilePrototype
@export var ramp_west: WorldTilePrototype
@export var cliff_side: WorldTilePrototype
@export var cliff_inner_corner: WorldTilePrototype
@export var cliff_outer_corner: WorldTilePrototype
```

```gdscript
class_name WorldTilePalette
extends Resource

@export var id: StringName
@export var display_name: String
@export var prototypes: Array[WorldTilePrototype] = []
@export var wall_sets: Array[WorldWallTileSet] = []
@export var surface_sets: Array[WorldSurfaceTileSet] = []
```

## 资源目录布局

新增资源目录建议：

```text
godot/resources/world_tiles/
  prototypes/
    building_wall/
      corner.tres
      straight.tres
      end.tres
      t_junction.tres
      cross.tres
      isolated.tres
      floor_flat.tres
    surface_placeholder_basic/
      flat.tres
      ramp_north.tres
      ramp_south.tres
      ramp_east.tres
      ramp_west.tres
      cliff_side.tres
      cliff_inner_corner.tres
      cliff_outer_corner.tres
    prop_placeholder_basic/
      table_metal.tres
      shelf_metal.tres
      ...
  sets/
    building_wall.tres
    building_wall_floor.tres
    surface_placeholder_basic_default.tres
  palettes/
    default_world_tile_palette.tres
```

`prototypes` 保存单个可放置资产。`sets` 保存建筑墙组和地表组。`palettes` 保存编辑器窗口使用的顶层集合。

## 现有字段映射

当前 JSON：

```json
{
  "prototypes": {
    "building_wall/straight": {
      "source": {
        "path": "builtin:world_tile:building_wall/straight"
      }
    }
  },
  "wall_sets": [
    {
      "id": "building_wall",
      "straight_prototype_id": "building_wall/straight"
    }
  ]
}
```

迁移后：

```text
WorldTilePrototype.id = &"building_wall/straight"
WorldTilePrototype.scene = ExtResource("res://assets/world_tiles/building_wall/straight.gltf")

WorldWallTileSet.id = &"building_wall"
WorldWallTileSet.straight = ExtResource("res://resources/world_tiles/prototypes/building_wall/straight.tres")
```

地图建筑当前仍可保留：

```gdscript
wall_set_id = "building_wall"
floor_surface_set_id = "building_wall/floor"
```

后续再逐步引入直接 Resource 引用：

```gdscript
@export var wall_set: WorldWallTileSet
@export var floor_surface_set: WorldSurfaceTileSet
```

在兼容期内，`MapBuilding3D.to_definition()` 仍输出旧的 id 字段，避免破坏运行时规则、smoke 和存档。

## 迁移阶段

### 资源类型落地

新增 `WorldTilePrototype`、`WorldWallTileSet`、`WorldSurfaceTileSet`、`WorldTilePalette`。先不改现有 JSON 加载路径，只补 Resource 类型和最小 headless load smoke。

验收：

- Godot 静态解析通过。
- 空白 `.tres` 或手写样例 `.tres` 可被 `ResourceLoader.load()` 正常加载。
- agent 报告能列出新增 Resource 类型和样例资源引用。

### JSON 到 Resource 转换工具

新增 Godot headless 工具脚本，从 `data/world_tiles/*.json` 生成 `.tres`：

```text
godot/scripts/tools/world_tile_resource_migration.gd
```

工具职责：

- 读取 `ContentRegistry.get_library("world_tiles")`。
- 为每个 prototype 生成 `WorldTilePrototype.tres`。
- 为每个 `wall_sets` 项生成 `WorldWallTileSet.tres`。
- 为每个 `surface_sets` 项生成 `WorldSurfaceTileSet.tres`。
- 生成 `default_world_tile_palette.tres`。
- 使用 `ResourceSaver.save()` 写入，避免手写 ext_resource id 出错。
- 输出转换报告到 `.local/agent-reports/world_tile_resource_migration/`。

验收：

- 生成资源数量和 JSON prototype / set 数量一致。
- 所有 `scene` 和 set 引用可加载。
- 生成文件为文本 `.tres`，不生成 `.res`。

### Palette 读取 Resource

调整 `CDC Map Tile Palette`：

- 优先加载 `res://resources/world_tiles/palettes/default_world_tile_palette.tres`。
- 若 Resource 缺失或加载失败，fallback 到当前 `ContentRegistry.get_library("world_tiles")`。
- UI 分类继续提供 `Building Tiles`、`Surface Tiles`、`Props`、`Markers`。
- 放置行为不变，仍创建 scene/node 实例并设置 `owner`。

验收：

- Editor 插件 smoke 通过。
- Palette 能显示 Resource 来源的 prototype。
- 删除或临时移走 palette resource 后，JSON fallback 仍可用。

### 地图建筑字段兼容升级

扩展 `MapBuilding3D`：

- 保留 `wall_set_id` 和 `floor_surface_set_id`。
- 新增可选 `wall_set: WorldWallTileSet` 和 `floor_surface_set: WorldSurfaceTileSet`。
- Inspector 优先展示 Resource 字段，旧 id 字段作为兼容和导出用字段。
- `to_definition()` 优先从 Resource 的 `id` 输出旧 schema 字段。

这一步只改变编辑体验，不改变运行时 map definition。

验收：

- 打开已有地图不丢字段。
- 保存地图后 scene smoke 通过。
- `to_definition()` 输出与迁移前关键字段一致。

### 校验和报告切换

扩展工具：

- `ContentRecordValidator` 保留 JSON 校验，迁移期继续检查旧数据。
- 新增 Resource 校验脚本，检查 `.tres` 的 id、引用、重复项、缺失 scene、set 空槽位。
- `godot-agent-report.ps1 -Kind Scenes` 可在 scene 引用中识别 `WorldTilePrototype` / `WorldWallTileSet`。
- `content_asset_manifest.gd` 支持从 Resource palette 收集 tile 资产引用。

验收：

- `tools/agent/test-godot-static.ps1 -Scenario CheckOnly` 通过。
- `tools/agent/test-godot-editor.ps1` 通过。
- `tools/agent/test-godot-game.ps1 -Scenario Scene` 通过。
- `git diff --check` 通过。

### 权威源切换

当 Resource 路径稳定后，明确权威源：

- `godot/resources/world_tiles/**/*.tres` 成为地图 tile 数据权威源。
- `data/world_tiles/*.json` 降级为迁移备份或外部工具兼容输入。
- `ContentRegistry.get_library("world_tiles")` 不再是 Palette 的主数据入口。
- 新增 `data/world_tiles` 修改时，需要转换工具或校验脚本提示其不是当前权威源。

验收：

- 新增 tile 只需创建 `.tres` 和对应 glTF 资源。
- Palette、asset manifest、scene smoke 不依赖 JSON 即可通过。
- 文档更新 `docs/agent-workflows/edit-map.md` 和 `tools/agent/README.md`，说明地图 tile 资产编辑入口。

## 命名调整

为避免和 Godot 原生 `TileSet` 混淆，迁移中逐步替换文档和新 API 中的模糊命名：

- `tile_set` 在新 Resource 侧使用 `wall_set`、`surface_set` 或 `tile_palette`。
- `world_tiles` 保留为资产域名和目录名。
- `MeshLibrary` 只在文档中作为“不使用”的对照概念出现。
- `GridMap` 只在文档中作为“不迁移”的对照概念出现。

旧 map definition 的 `props.building.tile_set` 字段可在兼容期保留，不做破坏性重命名。

## Agent 读写策略

`.tres` 是文本格式，agent 可以直接读写和 diff。但正式批量生成应优先走 Godot `ResourceSaver.save()`：

- 手写 `.tres` 适合小修、审查和紧急修正。
- 批量生成、迁移和重排引用使用 headless 工具。
- 禁止生成 `.res` 作为权威数据，因为二进制资源不利于 agent 审查。
- 生成工具需要输出报告，列出新增、更新、跳过和失败的资源。

## 风险与缓解

资源双写风险：

- 缓解：迁移期明确 Resource 优先、JSON fallback；权威切换后文档写清楚 JSON 只作备份。

`.tres` ext_resource id 手写错误：

- 缓解：批量转换使用 `ResourceSaver.save()`，不要用字符串模板生成。

场景保存造成大规模 diff：

- 缓解：先迁移 palette 和 resource，不立即批量打开保存所有地图；地图字段升级分批进行。

旧工具依赖 JSON：

- 缓解：保留 `ContentRegistry` fallback，逐个迁移 `content_asset_manifest`、validator、reporter 和 Palette。

Godot Inspector 中 Resource 数组编辑不够顺手：

- 缓解：继续让 `CDC Map Tile Palette` 成为主编辑入口，Resource Inspector 作为底层资产编辑入口。

## 测试计划

基础静态验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly
```

转换工具验证：

```powershell
D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/world_tile_resource_migration.gd -- --dry-run
D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/world_tile_resource_migration.gd
```

Editor 插件验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1
```

地图运行时验证：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Scene
```

内容和引用验证：

```powershell
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed
pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scenes
```

最终提交前：

```powershell
git diff --check
```

## 推荐实施顺序

优先做 Resource 类型和转换工具，因为它们不改变运行时行为。随后让 `CDC Map Tile Palette` 读取 Resource palette，确认编辑器体验收益。最后再让 `MapBuilding3D` 暴露 Resource 字段，并在稳定后宣布 `godot/resources/world_tiles/**/*.tres` 成为地图 tile 数据权威源。

这条路线能把地图 tile 数据变得更 Godot 原生，同时保留当前 scene/node 地图架构、agent 可维护性和现有运行时稳定性。
