# 大地图与场景管理优化计划

## 背景

当前项目已经完成一版新的地图架构：

- 露天世界统一通过 `res://scenes/locations/game_world_root.tscn` 进入。
- 露天地点之间通过大地图与小地图无缝缩放切换，不再切换根场景。
- 室内/地牢场景仍然保持独立，通过入口交互点整场景切换。
- 地图元数据集中在 `res://modules/map/map_module.gd` 与 `res://data/json/map_locations.json`。

这套架构已经能跑通主链路，但从可扩展性、性能、编辑体验和数据安全性上，还有一批值得继续推进的优化项。本文用于整理后续排期。

相关入口：

- `res://scenes/locations/game_world_root.tscn`
- `res://scripts/locations/game_world_root.gd`
- `res://scripts/locations/game_world_3d.gd`
- `res://scripts/locations/game_subscene_base.gd`
- `res://modules/map/map_module.gd`
- `res://core/game_state.gd`
- `res://data/json/map_locations.json`
- `res://data/json/map_data.json`

## 当前已具备

### 露天世界统一入口

- 主菜单新游戏与继续游戏统一进入 `game_world_root`。
- 大地图与露天小地图已经归入同一运行时根场景。
- 大地图点击露天地点后，可完成大地图移动并进入目标露天地点。

### 露天与室内分层

- 露天地点通过 `location_kind = outdoor` 进入统一根场景管理。
- 室内场景通过 `location_kind = interior` 独立切场景。
- 室内返回露天后，可直接恢复到指定露天地点与返回 spawn。

### 基础状态管理

- `GameState` 已经区分 `outdoor_root` / `interior` / `dungeon`。
- 已有 `active_outdoor_location_id`、`current_subscene_location_id`、`return_outdoor_spawn_id` 等状态。
- 已有大地图 cell、镜头 zoom、局部坐标等基础存档字段。

### 基础交互能力

- 已有 `EnterOverworldInteractionOption`。
- 已有 `EnterSubsceneInteractionOption`。
- 已有 `ExitToOutdoorInteractionOption`。

## 建议优先级

### 当前 P1：高价值，建议优先做

- 露天地点实例缓存与复用
- 室内/露天返回状态增强
- 大地图代理层与地点可视化增强
- 地图配置校验工具
- 场景切换与模式切换自动化测试补强

### 当前 P2：中价值，建议在 P1 后推进

- 多露天地点预加载与轻量 streaming
- 大地图道路/地形表现增强
- 地图编辑器辅助预览
- 子场景入口/出口标准化
- 地点状态持久化拆分

### P3：体验增强，可按需推进

- 大地图旅行演出增强
- 地点图标、标签、fog 表现打磨
- 露天地点背景模拟与远景音效
- 更复杂的多层地牢恢复链路

## 推荐优化项

### 1. 露天地点实例缓存与复用

当前 `game_world_root` 在切换露天地点时，主要还是围绕“当前只保留一个露天实例”展开。这个版本简单稳定，但还有两个问题：

- 每次在露天地点之间移动，目标地点都会重新实例化。
- 后续如果地点内容变复杂，频繁加载/释放会带来卡顿和状态恢复成本。

建议下一步升级为“小规模实例缓存”：

- 始终保留当前露天地点实例。
- 最近访问过的 1 到 2 个露天地点保留为 `inactive + reduced detail`。
- 远处地点只保留代理，不保留完整实例。
- 超过缓存上限时，按距离或最近最少使用策略回收旧实例。

建议新增接口：

- `WorldLocationRuntimeEntry`
  - 记录 `location_id`、`instance`、`detail_level`、`is_active`、`last_access_time`
- `WorldStreamingController`
  - 从 `game_world_root.gd` 中拆分出来，单独负责实例缓存、激活、回收

收益：

- 露天地点往返更顺滑。
- 后续接入更复杂地点状态时，不需要每次整场景重建。

### 2. 室内/露天返回状态增强

当前室内返回露天，已经支持基于 `return_outdoor_location_id` 和 `return_outdoor_spawn_id` 恢复，但仍然偏“入口级恢复”。后续建议补全为“露天上下文快照”：

- 进入室内时，记录：
  - 当前露天地点 id
  - 玩家露天局部位置
  - 当前 world mode
  - 当前相机缩放值
  - 当前露天地点局部 runtime 状态
- 返回露天时，优先恢复原始上下文，而不是只依赖一个固定 spawn 点

建议新增数据结构：

- `outdoor_resume_snapshot`
  - `location_id`
  - `player_local_position`
  - `camera_zoom_level`
  - `world_mode`
  - `entry_source_id`

收益：

- 同一个建筑有多个入口时，返回行为更自然。
- 后续做地下入口、楼梯、通风井等多出口返回会更稳。

### 3. 大地图代理层与地点可视化增强

当前大地图上地点主要以统一的圆柱 marker 展示，足够跑逻辑，但还不够表达地图信息。建议把代理层正式产品化：

- 每个露天地点支持专属代理资源：
  - 低模建筑
  - 地表底板
  - 地点 icon
  - 危险等级颜色
  - 解锁/未解锁状态视觉区分
- 支持道路段、关键地标、区域边界可视化。
- 支持当前位置、目标地点、旅行路径的高亮。

建议在 `map_locations.json` 中继续扩展：

- `proxy_scene_path`
- `marker_style`
- `map_icon`
- `danger_color`
- `label_offset`

收益：

- 大地图阅读性明显提升。
- 以后做 faction 控制区、事件热点、任务标记更容易落地。

### 4. 地图配置校验工具

当前地图配置已经比过去复杂很多，后续最容易出问题的不是逻辑本身，而是数据表和场景资源对不上。建议加一个统一校验工具，至少检查：

- `scene_path` 是否存在
- `entry_spawn_id` 是否在目标场景中存在
- `return_spawn_id` 是否在父露天场景中存在
- `parent_outdoor_location_id` 是否有效
- `location_kind` 是否合法
- `world_origin_cell` / `world_size_cells` 是否缺失
- 露天地点是否存在重叠范围
- 大地图可点击地点是否都能在 `overworld_walkable_cells` 上找到通路

建议形式：

- 一个独立 GDScript 校验入口
- 或一个 `tools/verify_map_locations.py` 脚本
- 也可以作为 `tests/sanity` 的扩展测试

收益：

- 地图扩展时更不容易因配置错误导致运行时才发现问题。

### 5. 露天地点 runtime 状态持久化拆分

当前 `GameState` 已经能保存“玩家当前在哪”和“如何返回”，但地点本身的运行时状态还没有系统化拆分。后续建议按“地点状态”维度单独存：

- 掉落物是否已拾取
- 容器是否已打开
- 门是否已开启
- 某些一次性事件是否已触发
- 某个露天地点的敌人刷新状态

建议新增：

- `location_runtime_state_by_id: Dictionary`
- `get_location_runtime_state(location_id)`
- `set_location_runtime_state(location_id, patch_data)`

原则：

- 露天地点与室内/地牢都用同一套 runtime state 接口
- 场景实例只读写自己的状态切片
- `GameState` 负责统一存档序列化

收益：

- 露天缓存和整场景切换都能共享同一套状态恢复方式。

### 6. WorldRoot 拆分为更清晰的控制器

当前 `game_world_root.gd` 已经承载了很多职责：

- 大地图点击输入
- 露天地点加载
- 模式切换
- 镜头过渡
- marker 刷新
- 旅行路径移动

为了避免后续文件过快膨胀，建议在下一轮拆为几个明确控制器：

- `WorldModeController`
  - 管模式状态机、缩放切换、输入锁定
- `WorldStreamingController`
  - 管露天地点实例加载、缓存、卸载
- `OverworldPresentationController`
  - 管 marker、路径、proxy、UI 标签
- `OutdoorTravelController`
  - 管大地图路径移动、旅行成本、到达回调

收益：

- 职责边界更清楚。
- 后续多人协作时更不容易互相冲突。

### 7. 子场景入口/出口标准化

当前入口交互已经可用，但还偏“以具体组件为中心”。后续建议形成统一约定，所有室内/地牢入口都遵守同一套数据格式：

- `target_location_id`
- `return_spawn_id`
- `entry_label`
- `transition_style`
- `requires_unlock_flag`
- `requires_item`

同时建议统一一个基类或 helper：

- `SubsceneTransitionConfig`
- `SubsceneTransitionService`

这样后面做这些内容会更快：

- 需要钥匙的门
- 任务完成后解锁的地下室
- 只出不进的逃生口
- 从不同楼梯返回不同 outdoor spawn

### 8. 大地图道路与真实可达性模型增强

当前大地图格子移动已经可用，但通行逻辑还偏基础。后续可以增强为更明确的“道路网络”：

- 区分主路、支路、危险路段
- 支持桥梁、路障、临时封锁
- 支持不同地点之间的旅行权重和特殊事件概率
- 支持“同样可达，但有更安全路径/更快路径”

建议扩展 `map_data.json`：

- `overworld_edges`
- `road_type`
- `travel_weight`
- `travel_risk_bonus`
- `blocked_by_flags`

收益：

- 后续可以做更有层次的探索和旅行决策。

### 9. 编辑器预览工具

现在露天地点仍然可以单独编辑，这是正确方向。下一步建议补一个“世界布局预览工具”，但不把它变成主要编辑入口：

- 在编辑器里只读显示所有露天地点的：
  - `world_origin_cell`
  - `world_size_cells`
  - `overworld_cell`
  - 代理占位
- 高亮重叠区域
- 高亮没有道路连接的孤立地点
- 一键跳到对应地点场景

收益：

- 地图规模变大后，设计师能更快检查整体布局，而不是靠手算坐标。

### 10. 测试覆盖继续补强

当前已有基础的 functional test，但对关键流转还不够。建议补以下测试：

- 新游戏进入 `game_world_root`
- 继续游戏进入室内时，加载正确的室内场景
- 室内返回露天后，恢复到正确地点和返回点
- 露天地点切换后，`GameState` 中的 `active_outdoor_location_id` 与 `world_mode` 正确更新
- 非露天地点不会出现在大地图可点击列表中
- `map_locations.json` 中所有室内场景都具备有效父露天地点
- 露天地点 world origin 不重叠
- 子场景入口配置缺失时给出清晰报错

## 暂不建议现在做

- 把室内/地牢也并进 `game_world_root` 做全无缝
- 为每个露天地点同时保留完整实例常驻
- 在还没有工具支持前，大规模手工维护世界坐标

这些方向要么成本高，要么会显著增加内存和维护复杂度，不适合作为当前阶段优先项。

## 推荐下一步顺序

1. 地图配置校验工具
2. 室内/露天返回状态增强
3. `game_world_root` 拆分为多个控制器
4. 露天地点实例缓存与复用
5. 大地图代理层与地点可视化增强
6. 露天地点 runtime 状态持久化拆分
7. 编辑器预览工具
8. 大地图道路与真实可达性模型增强
