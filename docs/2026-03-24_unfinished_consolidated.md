# 2026-03-24 Unfinished Consolidated Backlog

本文件用于替代以下四份 2026-03-24 文档：

- `2026-03-24_remaining_tasks.md`
- `2026-03-24_bevy_headless_completion_plan.md`
- `2026-03-24_godot_legacy_cleanup_assessment.md`
- `2026-03-24_directional_suggestions.md`

目标是只保留截至当前仓库状态仍然**没有完成**、并且后续仍然需要继续推进的内容，避免同一批 backlog 和迁移判断分散在多个文档中。

## 已完成并因此不再重复列入

- `SimulationRuntime` 已补第一批正式 economy runtime surface：
  - `equip_item`
  - `unequip_item`
  - `reload_equipped_weapon`
  - `learn_skill`
  - `craft_recipe`
  - `buy_item_from_shop`
  - `sell_item_to_shop`
- `bevy_server` 的 economy smoke 路径已开始改为走 `SimulationRuntime` 入口，而不是只直接下钻 `economy`
- Item Fragment Editor 已补模板与复制工作流：
  - `New From Template`
  - `Duplicate Current Item`
  - `Clone Fragment Set`
- Godot 交互链路已补一轮 `LEGACY AUTHORITY BOUNDARY` 标记，明确其为兼容壳/前端壳而不是长期权威层
- 原 `remaining_tasks` 文档开头列出的已完成项仍视为完成，不再重复录入：
  - item editor 的基础引用预览、`Used By` 反查、可搜索引用选择、部分字段级校验路径映射
  - NPC AI 的 `utility` 分层拆分、`Cook` 最小职业样板、基础调试快照增强
  - `bevy_server` 的基础 NPC AI 调试输出
- NPC AI 的 Rust 侧第二职业样板已补到 `Doctor`，并完成：
  - `NpcUtilityContext` / `NpcPlanningContext` 边界收紧
  - `guard_actions` / `cook_actions` / `doctor_actions` / `common_life_actions` 动作拆分
  - reservation 独立服务层
  - `bevy_debug_viewer` AI HUD 页
  - AI 内容校验与批处理检查命令
  - doctor 角色样例数据与运行时验证

## 1. Rust / Bevy Headless 宿主继续收口

### 1.1 Runtime command surface 仍需继续收口

虽然第一批 economy 高频操作已经收进 `SimulationRuntime`，但这一阶段还没有完全完成：

- 继续减少 `bevy_server`、测试、debug 工具对 `economy_mut()` 的直接依赖
- 继续决定哪些 runtime 操作应升级为：
  - `SimulationCommand`
  - 或 `game_protocol` request
- 避免后续再把业务操作长期留在 demo helper 或直接子系统调用中

### 1.2 权威 save / load snapshot

- 在共享 Rust 层建立完整 runtime save model
- 至少覆盖：
  - actor registry
  - actor positions
  - AP / turn state
  - combat HP / progression
  - economy actor state
  - active / completed quests
  - current map id
  - interaction context
  - runtime-generated pickups / map object deltas
- 提供：
  - `save_snapshot()`
  - `load_snapshot()`
- 为 schema version / migration 预留升级位点

完成标准：

- 能从运行中的 runtime 导出 snapshot
- 能从 snapshot 重建等价 runtime
- 能校验存档前后：
  - actor 数量一致
  - 玩家背包一致
  - quest 状态一致
  - 地图对象变化一致
  - 当前地图上下文一致

### 1.3 权威 dialogue runtime

- 在 `rust/crates/game_data` 补齐或确认 dialogue library 的权威加载入口
- 在 `rust/crates/game_core` 增加 `DialogueRuntimeState`
- 将以下能力统一下沉到共享 Rust 层：
  - start dialogue
  - read current node
  - enumerate choices
  - choose option
  - apply node actions
  - advance to next node
  - end dialogue
- 让对话动作影响下列系统时由 Rust 直接结算：
  - quest
  - item
  - money
  - map travel
- 改造 `bevy_debug_viewer`，不再本地推进对话分支，只消费 `SimulationEvent` / `SimulationSnapshot`

### 1.4 权威 map travel / scene context runtime

- 在 `rust/crates/game_core` 增加统一地图切换入口
- 为以下交互建立统一 runtime 行为：
  - `enter_subscene`
  - `enter_overworld`
  - `exit_to_outdoor`
  - `enter_outdoor_location`
- 将以下内容接入共享上下文：
  - 返回点
  - outdoor resume
  - subscene resume
- 切换时同步更新：
  - `GridWorld`
  - 当前 map object 集
  - 交互对象
  - actor 位置
  - 当前上下文快照

### 1.5 角色交互配置数据化

- 在 `data/characters/*.json` 逐步补全显式 `interaction`
- 优先覆盖高频 NPC：
  - 商人
  - 医生
  - 守卫
- 让 `game_bevy` 组装层优先读取显式交互配置
- fallback 仅用于未迁移数据

### 1.6 gameplay 协议面与 `bevy_server` 长期宿主化

- 扩充 `game_protocol`，覆盖完整 headless gameplay 命令/事件面
- 至少包括：
  - runtime snapshot request
  - runtime delta / event push
  - equip / unequip / reload
  - craft / buy / sell
  - learn skill
  - start quest
  - advance dialogue
  - map travel
  - save / load
- 为失败场景补稳定错误语义
- 明确 command id / response / async event 关系

### 1.7 `bevy_server` 本地 transport

- 在 `rust/apps/bevy_server` 增加长期方案的本地 transport
- 优先 TCP 或 IPC 其一，不要并行维护两套长期主通道
- 支持：
  - world snapshot 订阅
  - request snapshot
  - command dispatch
  - runtime event stream
  - error channel
  - connect / disconnect / reconnect / load initial state
- 保持消息语义与 `SimulationCommand` / `SimulationEvent` 一致

### 1.8 交互调试与 headless 长链路验证

- 丰富 `bevy_debug_viewer` 交互调试面板
- 显示：
  - 完整 option payload
  - pending interaction
  - pending movement
  - inventory
  - 地图上下文
  - 对话动作结果
  - 不可执行交互的失败原因
- 增加交互专项测试：
  - 接近后自动执行 attack / talk / scene transition
  - 敌对切换时 interaction prompt 顺序变化
  - 地图对象切换后 prompt 刷新
  - 对话分支与动作节点共享运行时测试
- 增加完整 headless smoke scenarios，至少覆盖：
  - 开局载入
  - 地图移动
  - 拾取
  - 战斗击杀
  - quest 开始 / 推进 / 完成
  - 技能学习
  - 制作
  - 商店交易
  - 地图切换
  - 对话推进
  - 存档 / 读档

## 2. Godot 客户端迁移与 legacy 清理剩余项

### 2.1 Godot 协议前端化

- 基于 `game_protocol` 增加交互查询 / 执行 / 对话推进传输层
- 将 Godot 端收敛为：
  - 点击命中
  - 菜单 UI
  - 动画表现
  - 命令发送
  - 事件消费
- 不再恢复或扩展 GDScript 本地交互权威逻辑

### 2.2 旧交互实现的继续退役

当前只完成了 legacy 标记，还没有完成真正的退役和瘦身：

- `systems/interaction_system.gd` 仍需继续收敛为协议前端壳
- `modules/interaction/*` 仍需在协议前端稳定后分阶段瘦身
- `systems/player_controller.gd` 仍是最大的本地交互执行热点
- `modules/interaction/options/talk_interaction_option.gd` 仍持有本地对话执行分支
- `modules/interaction/options/attack_interaction_option.gd` 仍持有本地攻击入口分支
- travel 相关 option 仍直接调用 Godot 本地 `MapModule` / 场景切换路径

### 2.3 B 级 legacy 域后续整理

这些域当前不应直接删，但后续仍需整理边界：

- `core/game_state.gd`
  - 继续拆分 Rust 权威世界状态、Godot 只读缓存、UI 临时状态
- `modules/map/map_module.gd`
  - 拆开旅行规则与场景加载编排
- `systems/ai/ai_manager.gd`
  - 剥离决策循环和规则判断，保留 visual actor spawn / 表现桥接 / actor id 映射
- `core/data_manager.gd`
  - 继续移除共享 schema、校验、规则迁移等长期应归属 Rust 的职责

## 3. Item Fragment Editor 剩余项

### 3.1 引用预览能力收尾

- 为 item / effect 引用补 hover 预览
- 保持 badge 摘要、右侧 detail panel、picker 预览一致
- 继续补齐高频引用位点的详情入口

### 3.2 Shared Registries / Catalog Tightening

- 在共享 Rust 层建立 registry / catalog
- 收紧高频字符串字段：
  - `equipment slots`
  - `rarity`
  - `weapon subtype`
  - `usable subtype`
- 编辑器默认从 registry 选择
- 校验器对未知值输出 warning

### 3.3 Data Lint and Reporting

- 在共享 Rust 层增加内容质量 lint：
  - 未被任何 item 引用的 effect
  - 缺 icon 的 item
  - 缺 economy fragment 的 item
  - 可装备 item 无属性加成也无效果
  - placeholder effect 长期未补真实 payload
  - 高度重复 item 组合
- 在编辑器增加只读报告页：
  - `Items report`
  - `Effects report`
  - `Broken references`
  - `Unused content`

### 3.4 Fragment Header Quick Edit

- 在 fragment 卡片头部增加高频字段快速编辑
- 优先覆盖：
  - `economy.rarity`
  - `stacking.max_stack`
  - `equip.level_requirement`
  - `usable.use_time`
  - `weapon.damage`

### 3.5 测试补齐

- 前端测试：
  - 新建 item 并添加 `equip + usable`
  - 保存后重载字段不丢失
  - 删除 fragment 后 UI 状态与 validation 同步
  - picker 写回真实 id
  - fragment 摘要随关键字段更新
- workspace / host 集成测试：
  - `load_item_workspace` 正确返回引用数据
  - save 时按最终 item 集合做交叉引用校验
  - effect / item 引用错误能稳定映射到前端 issue

## 4. NPC AI 剩余项

当前 AI backlog 中，Rust / Bevy 侧已完成；剩余项只保留 Godot 只读表现同步。

### 4.1 Godot 只读表现同步

- 输出 NPC 当前目标、动作、动作阶段、地点锚点、值班状态、警戒状态、睡眠状态
- Godot 侧只消费状态，不复制规划逻辑

## 5. 继续沿用的推进原则

以下原则仍然有效，后续实现应继续遵守：

- 继续保持三端分离：
  - `逻辑` 在 Rust / Bevy
  - `表现` 在 Godot
  - `编辑` 在独立工具
- 不要为了短期方便把未来属于 Rust / Bevy 的核心逻辑重新耦合回 Godot
- 保持共享 Rust 模型作为内容 schema 与运行时交换结构的权威来源
- 当前阶段优先级仍然是：
  1. 让 `bevy_server` 成为完整逻辑宿主
  2. 让 `SimulationRuntime` 成为统一 headless 入口
  3. 让 `game_protocol` 成为外部驱动入口
  4. 最后再接 Godot / debug viewer / UI

## 6. 推荐后续顺序

若按当前仓库状态继续推进，推荐优先顺序如下：

1. `save / load snapshot`
2. `dialogue runtime`
3. `map travel / scene context runtime`
4. `game_protocol` 完整 gameplay surface
5. `bevy_server` 本地 transport
6. Godot 协议前端化
7. NPC AI 的 Godot 只读表现同步
8. Item Editor 的 lint / report / registry 收紧 / 测试补齐

## 7. 文档用途

从现在开始，若需要继续维护 2026-03-24 这一批工作项，应只更新本文件，不再恢复已删除的四份分散文档。
