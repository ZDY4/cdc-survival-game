# bevy_map_editor 建筑不渲染问题修复方案

## 问题概述

`survivor_outpost_01` 中建筑在 `bevy_map_editor` 里看起来“没有渲染出来”，但问题并不在地图数据、建筑生成、静态场景转换或 building wall instancing 逻辑本身，而是在运行时资产根目录配置。

`bevy_map_editor` 当前使用默认 `AssetPlugin` 行为，没有显式把资产根目录指向仓库的 `rust/assets`。因此运行时 `AssetServer` 会默认从：

- `rust/apps/bevy_map_editor/assets`

加载 glTF / 材质 /纹理资源。

但项目里的 tile 资产和占位模型实际位于：

- `rust/assets/world_tiles/...`
- `rust/assets/container_placeholders/...`

这会导致 `bevy_map_editor` 无法加载建筑墙体和建筑地板对应的 glTF 资源。

## 已确认现象

运行 `bevy_map_editor` 时，日志中出现如下路径错误：

- `Path not found: G:\Projects\cdc_survival_game\rust\apps\bevy_map_editor\assets\world_tiles/building_wall_legacy/corner.gltf`
- `Path not found: G:\Projects\cdc_survival_game\rust\apps\bevy_map_editor\assets\world_tiles/building_wall_legacy/straight.gltf`
- `Path not found: G:\Projects\cdc_survival_game\rust\apps\bevy_map_editor\assets\world_tiles/building_wall_legacy/end.gltf`
- `Path not found: G:\Projects\cdc_survival_game\rust\apps\bevy_map_editor\assets\world_tiles/building_wall_legacy/floor_flat.gltf`
- `Path not found: G:\Projects\cdc_survival_game\rust\apps\bevy_map_editor\assets\container_placeholders/*.gltf`

而这些文件真实存在于：

- `G:\Projects\cdc_survival_game\rust\assets\world_tiles\building_wall_legacy\*.gltf`
- `G:\Projects\cdc_survival_game\rust\assets\container_placeholders\*.gltf`

## 根因

`game_bevy::world_render` 和相关内容定义长期约定统一从 `rust/assets` 加载资产。

`bevy_debug_viewer` 已经显式配置了 `AssetPlugin.file_path`，把资产根目录指向 bootstrap 中提供的 asset dir，因此它能正确解析：

- `world_tiles/building_wall_legacy/*.gltf`
- `container_placeholders/*.gltf`

但 `bevy_map_editor` 没有做同样的配置，导致同一套 shared world render 在两个 app 中出现了不同的运行时资产根目录。

这和项目当前“三端分离 + Rust / Bevy 共享权威渲染链”的方向不一致，因为：

- shared `game_bevy::world_render` 已经统一
- 资产定义也统一到了 shared prototype / tile catalog
- 但 app 层 asset root 仍然分裂，造成 shared 渲染链在 `bevy_map_editor` 中失效

## 影响范围

该问题不仅影响 `survivor_outpost_01`。

凡是 `bevy_map_editor` 中通过 `AssetServer` 从相对路径加载 `rust/assets` 下资源的内容，都会受到影响，包括但不限于：

- 建筑墙体 tile
- 建筑地板 tile
- 容器占位模型
- 后续新增的 shared world tile / prop / placeholder 资源

因此这不是单地图问题，而是 `bevy_map_editor` 的全局资产入口配置问题。

## 推荐修复方案

### 方案目标

让 `bevy_map_editor` 与 `bevy_debug_viewer` 一样，显式把 Bevy 资产根目录指向仓库的 `rust/assets`，从而保证 shared `game_bevy` 渲染链在不同 app 中使用同一套资产根。

### 推荐做法

在 `rust/apps/bevy_map_editor/src/main.rs` 的 `DefaultPlugins` 配置中，增加 `AssetPlugin` 设置，显式指定：

- `file_path = repo_root()/rust/assets`

实现方式应尽量与 `bevy_debug_viewer` 保持一致，避免再出现 app 之间各自维护不同资产根目录逻辑。

更具体地说：

1. 为 `bevy_map_editor` 提供一个稳定的 asset dir 解析方式。
2. 在 app 初始化时，将 `DefaultPlugins` 中的 `AssetPlugin.file_path` 指向该目录。
3. 保持 `game_bevy`、`game_data` 中现有相对资产路径不变，例如：
   - `world_tiles/building_wall_legacy/corner.gltf`
   - `container_placeholders/crate_wood.gltf`

这样改动最小，也最符合 shared 资产路径的当前设计。

## 不推荐的方案

以下方案不建议采用：

### 1. 把资源复制到 `rust/apps/bevy_map_editor/assets`

不推荐原因：

- 会制造第二套资产根目录
- 会让 `bevy_map_editor` 和 `bevy_debug_viewer` 使用不同资源来源
- 会增加同步成本和失配风险

### 2. 为 `bevy_map_editor` 单独改写 tile / prop 路径

不推荐原因：

- 会把 shared 渲染链重新切回 app 私有分支
- 会破坏 `game_bevy` 作为共享 Bevy 运行时装配层的边界
- 后续维护成本更高

### 3. 为缺失资产增加 box fallback 作为正式修复

不推荐原因：

- 只能掩盖问题，不能修复真实资产入口错误
- 会让正式渲染问题退化成“看起来能显示”的假成功
- 与当前“不要再把 shared 内容回退成临时 box 表示”的方向冲突

## 修复后的预期结果

修复完成后，`bevy_map_editor` 应满足以下结果：

- `survivor_outpost_01` 中建筑墙体正常显示
- 建筑地板 tile 正常显示
- 容器等占位模型正常显示
- 运行日志中不再出现 `rust/apps/bevy_map_editor/assets/...` 下的 `Path not found`
- `bevy_map_editor` 与 `bevy_debug_viewer` 对 shared 资产路径的解释保持一致

## 最小验证步骤

建议用以下方式验证：

1. 运行 `cargo run -p bevy_map_editor`
2. 打开 `survivor_outpost_01`
3. 观察建筑墙体和建筑地板是否可见
4. 检查控制台日志，确认不再出现以下路径加载错误：
   - `world_tiles/building_wall_legacy/*.gltf`
   - `container_placeholders/*.gltf`
5. 额外抽查一张包含容器或其他 tile 模型的地图，确认不是仅修复了单一 building wall 资源

## 与项目方向的关系

这次修复属于 shared Bevy 渲染链落地的一部分。

它服务于以下目标：

- 让 `bevy_map_editor` 与 `bevy_debug_viewer` 真正共享 `game_bevy::world_render`
- 让资产来源继续统一到 `rust/assets + game_data prototype definitions`
- 避免在 app 层重新分叉出私有资产路径规则

该修复不改变 shared 数据模型，也不引入新的跨端耦合；它只是把 `bevy_map_editor` 的运行时资产入口对齐到现有 shared 设计。

## 自然的下一步

完成该修复后，建议顺手补一项最低成本的保护：

- 为 `bevy_map_editor` 和 `bevy_debug_viewer` 统一抽出一个 shared asset dir 解析入口

这样可以避免未来又出现某个 Bevy app 忘记配置 `AssetPlugin.file_path`，导致 shared 渲染链在不同入口表现不一致。
