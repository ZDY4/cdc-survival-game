# Instanced Tile-Based 3D World 完整框架线

## 背景

当前项目已经完成了这条路线上的前置基础：

- 建筑墙已经从旧 `box` 语义迁到 `building_wall_tiles`
- `bevy_debug_viewer` 和 `bevy_map_editor` 已统一复用 shared `game_bevy::world_render`
- tile prototype 已支持从 glTF scene flatten 成多 primitive runtime batch
- `Standard` tile 已接入 shared custom instancing backend
- 建筑墙也已接入 shared batch / instanced render，同时 viewer 保留单格 pick / outline / occlusion 粒度

现在的下一阶段目标，不再是“只修建筑墙”，而是把整套世界静态渲染能力收口成一个可长期演进的 **tile-based 3D world framework**。

本文定义这条“完整框架线”的剩余 5 个阶段。

## 总目标

形成一套统一框架，使以下内容都通过共享 tile/prototype/placement 体系表达和渲染：

- 建筑墙
- 建筑地板
- 地表与高低起伏
- 环境物件
- 可交互场景物件的静态态
- overworld 地块

并满足以下约束：

- `Rust / Bevy` 是唯一长期实现基准
- `bevy_debug_viewer` 和 `bevy_map_editor` 不保留独立世界内容渲染链
- 正式静态世界主渲染尽量不依赖 `StaticWorldBoxSpec`
- runtime 允许一部分实例从 instanced 静态态“升格”为独立动态实体
- 资产来源长期统一为 `rust/assets + game_data prototype definitions`

## 当前完成位置

当前已经完成的是“建筑墙专用链 + shared batch / instancing 基础打通”。

从完整框架视角看，当前相当于：

- 已完成建筑墙的专用 shared 渲染收口
- 已完成 instanced tile runtime 的第一版批次骨架
- 尚未完成地表 / floor / prop / 动态升格 / 资产流水线 / 最终收口

因此，完整框架线还剩 5 个阶段。

---

## 阶段 1：静态世界内容全面并入 Tile World

### 目标

把当前仍然散落在 `box` / ground patch / 独立实体路径中的静态世界内容，统一并入 shared tile world。

### 范围

- 建筑地板从 `BuildingFloor box` 改成 surface tile placement
- 地表与高低起伏改成 surface tile placement
- 环境静态物件统一走 prop prototype placement
- overworld 地块尽可能转到 surface / prototype placement

### 这一步完成后应满足

- 静态世界的主要可见内容都来自 `TileWorldSceneSpec`
- `resolve_tile_world_scene()` 成为大部分静态世界几何的主入口
- `spawn_world_render_scene()` 中的通用 `spawn_box()` 只剩少量过渡/调试职责

### 主要实施点

- 在 `game_data` 明确 surface set / elevation / slope 的权威字段
- 在 `game_bevy::tile_world` 新增地表解析规则
- 在 `game_bevy::world_render` 中为 surface / prop prototype 扩大 instanced batch 覆盖面
- map editor / viewer 不单独加私有地表渲染逻辑

### 验收标准

- 同一张地图中，建筑墙、建筑地板、地表、箱子/柜子等 prop 都来自 shared tile scene
- `scene.boxes` 不再承载正式静态主可见内容，只剩少量辅助语义
- `cargo check`
- `cargo test -p game_bevy -p bevy_debug_viewer`

---

## 阶段 2：清理剩余 Box / Fallback 主渲染路径

### 目标

把 shared / viewer / editor 中剩余“能回退成普通 box 渲染正式世界内容”的路径清理掉。

### 范围

- 清理 shared `StaticWorldBoxSpec` 中不再需要的正式主渲染语义
- 清理 viewer 对 shared box 的老兼容分支
- map editor 继续只依赖 shared world render，不新增私有回退能力

### 保留的 box 用途

本阶段结束后，`box` 只应承担以下职责：

- pick proxy
- outline proxy
- 临时调试可视化
- 少量尚未 tile 化的过渡辅助

### 这一步完成后应满足

- 正式世界几何不再依赖 `spawn_box()` 作为主路径
- “某个建筑/地表/物件因为 fallback 被渲染成普通长方体”不再是默认可发生情况

### 主要实施点

- 缩减 `StaticWorldMaterialRole` 中仅为老 box fallback 服务的分支
- viewer `collect_static_world_box_specs()` 只保留真正的 proxy / debug 内容
- 清理无调用方的旧 helper

### 验收标准

- viewer / editor 中建筑墙、地板、地表、环境物件都不会再退回普通 box 外观
- `cargo check`
- 手动 smoke：shared render 和 viewer/editor 显示一致

---

## 阶段 3：实例升格为独立动态实体

### 目标

解决“instanced 静态世界”和“可交互 / 可动画 / 可破坏 / 可物理模拟对象”之间的运行时冲突。

### 核心原则

不是所有对象都永久 instanced。

正确模型是：

- 静态时：作为 instanced placement 存在
- 激活时：从 batch 中脱离，升格为独立实体
- 动作结束后：可选择保持独立，或回收到 batch

### 需要支持的对象类型

- 箱子 / 柜子打开
- 门类动画
- 可破坏物件
- 进入物理模拟的对象
- 有独立 runtime state 的环境机关

### 建议的实例状态分类

- `StaticInstanced`
  - 永远 batch
- `ReactiveInstanced`
  - 默认 batch，交互时升格
- `DynamicUnique`
  - 从一开始就是独立实体

### 主要实施点

- 在 shared runtime 引入“实例句柄 -> 动态实体”的切换机制
- 让 viewer / game runtime 能隐藏指定 batch instance
- 为 prototype definition 增加 behavior / upgrade policy 元数据
- 为动态实体保留与原 map object / tile instance 的语义绑定

### 这一步完成后应满足

- 可交互静态物件默认走 instanced
- 触发动画或破坏时，实例可无缝切到独立实体
- pick / outline / occlusion / interaction 语义在切换前后保持稳定

### 验收标准

- 一个 instanced 柜子可被交互，交互后变成独立动态实体
- 一个可破坏场景物件可从静态实例切为破坏态实体
- viewer 中 hover / outline 不因升格丢失目标语义

---

## 阶段 4：补完整 Prototype / TileSet / Behavior Schema

### 目标

把当前“够用但还偏首版”的 prototype 内容模型，补成长期稳定 schema。

### 需要补充的结构方向

- prop prototype metadata
- wall set / surface set 的完整约定
- prototype bounds / pivot / facing 规范
- 可交互行为入口
- 动画资源绑定入口
- 破坏态/替换态入口
- pick proxy / occluder policy

### 设计原则

- 内容权威放在 `game_data`
- runtime 只消费 schema，不做 viewer 私有推断
- 新增 prototype / set 不要求改 shared 渲染框架 API

### 主要实施点

- 扩展 `WorldTilePrototypeDefinition`
- 扩展 wall/surface set 内容定义
- 为 map object visual spec 和 building tile set spec 补完整字段
- 加强内容校验和引用完整性检查

### 这一步完成后应满足

- 新增一种墙体、地表或环境物件，不需要再改 renderer 结构
- 内容数据可以显式描述对象是静态实例、可升格实例还是独立动态对象

### 验收标准

- `game_data` 中 prototype / set / behavior 的 schema 能覆盖现有世界内容
- 缺失引用、无效 prototype id、非法组合都会在加载时明确报错

---

## 阶段 5：补完整离线资产流水线与最终收口

### 目标

把当前 placeholder 资产 + 首版烘焙工具，扩展成正式可持续使用的资产流水线，并做最终性能与链路收口。

### 资产流水线要求

- 程序化 placeholder 可重复离线烘焙
- 正式美术资产能无缝替换 placeholder prototype
- prototype catalog 与实际 glTF 资产一致
- pivot / bounds / scene index / primitive flatten 行为可自动校验

### 最终收口要求

- viewer / map editor / shared render 行为一致
- shared tile batch 是静态世界渲染主干
- draw call / batch 数量可观测
- occlusion / fade / hover / outline / pick proxy 行为稳定

### 主要实施点

- 完善 `bake_world_tile_placeholders` 一类工具
- 加 asset validation / catalog validation
- 为 batch / instance 统计补 profiling 指标
- 做最后一轮无用旧链清理

### 这一步完成后应满足

- placeholder 到正式美术替换只改资产和内容定义，不改运行时拼接逻辑
- 运行时不再依赖程序化生成建筑墙 mesh
- tile-based 3D world 框架成为默认世界构造方式

### 验收标准

- `cargo check`
- `cargo test -p game_data -p game_bevy -p bevy_debug_viewer`
- viewer / editor 手动 smoke
- 至少一组正式或半正式美术 prototype 能替换 placeholder 并保持同样拼接逻辑

---

## 推荐实施顺序

建议严格按以下顺序推进：

1. 阶段 1：先把大多数静态世界内容并入 tile world
2. 阶段 2：再清旧 box/fallback，避免双轨长期并存
3. 阶段 3：然后补实例升格机制，解决动态对象问题
4. 阶段 4：再把 schema 补完整，避免中途频繁返工数据结构
5. 阶段 5：最后做资产流水线和全链收口

原因很直接：

- 如果先做动态升格，而静态世界本身还没统一进 tile world，会出现两套并存状态机
- 如果 schema 先过度设计，而静态渲染主干还没稳定，容易反复修改字段
- 如果太早做最终清理，容易把过渡工具链删掉导致中途施工困难

## 里程碑定义

### 里程碑 A：静态世界统一

完成阶段 1 + 阶段 2 后，达到：

- 建筑墙、地板、地表、环境物件大多走 shared tile world
- 正式世界外观基本脱离普通 box/fallback 路径

### 里程碑 B：运行时可扩展

完成阶段 3 后，达到：

- instanced 静态世界与动态交互对象可以共存
- 箱子/柜子/门/可破坏物件有稳定 runtime 路径

### 里程碑 C：正式框架闭环

完成阶段 4 + 阶段 5 后，达到：

- 内容 schema、资产流水线、shared render、viewer/editor、运行时动态切换都闭环
- 这套框架可以作为后续地图、建筑、地形、环境构造的长期基线

## 非目标

本路线默认不包括以下内容：

- Godot 端重建同样的 tile world 逻辑
- 为旧 Godot 世界内容链保留长期兼容双写
- 把所有动画都强行塞进 instancing
- 在 editor 本地重建一套私有 prototype/runtime 世界渲染逻辑

## 一句话结论

这条完整框架线的核心，不是“把所有东西都变成 instancing”，而是：

**把世界静态构造统一到 tile/prototype/placement，把运行时动态行为统一到实例升格机制，并让 shared render 成为 viewer 与 editor 的共同基线。**
