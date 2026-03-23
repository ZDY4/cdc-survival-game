# Bevy 交互迁移后续优化建议

本文记录本轮 `Bevy-first` 交互迁移完成后，下一阶段最值得继续推进的优化项，按“先补权威运行时，再补前端接入，最后补体验”的顺序整理。

## 当前已完成基线

- 共享交互 schema 已落到 `rust/crates/game_data/src/interaction.rs`
- `game_core` 已支持交互查询、交互执行、接近规划、交互上下文和交互事件
- `bevy_debug_viewer` 已成为新的调试型可玩交互入口
- `game_protocol` 已预留交互查询与执行消息

## P1：优先补齐的权威运行时能力

### 1. 把对话推进从 viewer 本地逻辑收回到 `game_core`

当前 `bevy_debug_viewer` 会直接读取 `data/dialogues/*.json` 并本地推进分支，这适合调试，但还不是运行时权威。

建议：

- 在 `game_data` 增加对话库加载入口
- 在 `game_core` 增加 `DialogueRuntimeState`
- 把“当前节点、可选分支、分支选择、终点动作”都放到共享 Rust 层
- viewer 改为只显示 `SimulationEvent` / `SimulationSnapshot` 中暴露的对话状态

收益：

- 后续 Godot、TCP 客户端、调试器都能复用同一套对话状态
- 不会再有 viewer 与正式前端行为分叉

### 2. 把场景切换从上下文写入升级为真实地图切换

这轮已经能更新 `InteractionContextSnapshot`，但还没有真正切换到另一张 Rust map。

建议：

- 在 `game_core` 增加地图切换命令
- 切换时刷新 `GridWorld`、地图对象、交互对象和 actor 位置
- 为 `enter_subscene` / `enter_overworld` / `exit_to_outdoor` / `enter_outdoor_location` 建立统一的地图切换入口
- 把返回点与 outdoor/subscene resume 信息接到共享上下文

收益：

- 交互结果不再只是“记录意图”，而是能驱动真正的 Bevy 运行时世界切换

### 3. 把角色交互配置从 fallback 规则逐步转为数据驱动

当前 NPC 交互仍有一部分依赖“友方默认 talk + attack，敌对默认 attack”的 fallback 逻辑。

建议：

- 在 `data/characters/*.json` 中逐步补 `interaction`
- 对商人、医生、守卫等角色明确声明显示名、对话 ID、交易入口、优先级和距离
- 让 `game_bevy` 组装层优先读取角色显式交互配置，fallback 仅用于未迁移数据

收益：

- 新交互行为不需要继续写死在代码里
- 更符合“共享 Rust 数据模型作为权威”的迁移方向

## P2：前端与协议接入

### 4. 把 Godot 输入前端改成协议客户端，而不是重新持有交互权威

如果后续还需要让 Godot 前端重新可玩，建议不要恢复 GDScript 交互逻辑，而是让它变成协议客户端。

建议：

- 基于 `game_protocol` 增加交互查询 / 执行 / 对话推进的传输层
- 让 Godot 只负责：
  - 点击命中
  - UI 菜单
  - 动画与表现
  - 向 Bevy 发送命令并消费事件

收益：

- 保持三端分离方向正确
- 避免再次把核心交互逻辑堆回 Godot

### 5. 为 `bevy_server` 增加真正的本地 TCP 传输实现

目前协议类型已具备，但 app 侧还没有完整 transport。

建议：

- 在 `bevy_server` 增加本地 TCP server
- 支持 world snapshot 订阅、交互 prompt 查询、交互执行、对话推进、地图切换事件推送
- 保持消息语义与 `SimulationCommand` / `SimulationEvent` 一致

收益：

- 后续 Godot、调试工具、编辑器都能统一接入

## P3：体验与调试工具

### 6. 丰富 `bevy_debug_viewer` 的交互调试面板

当前 viewer 已可用，但还偏简陋。

建议：

- 显示当前 target 的完整 option payload
- 显示当前 pending interaction / pending movement
- 在 HUD 中展示 inventory、当前地图上下文、对话动作结果
- 为不可执行交互明确显示失败原因

### 7. 增加交互专项测试覆盖

当前已覆盖基础场景，后续建议继续补：

- 接近后自动执行 attack / talk / scene transition
- 敌对切换时 interaction prompt 顺序变化
- 地图对象切换后 prompt 刷新
- 对话分支和动作节点的共享运行时测试

### 8. 清理 Godot 旧交互权威实现

这轮已经让 Rust/Bevy 成为交互权威，但 Godot 旧脚本仍保留在仓库里。

建议：

- 明确标记 `systems/interaction_system.gd`、`modules/interaction/*` 为 legacy
- 停止在新功能中继续扩展这些脚本
- 后续等 Godot 客户端改为协议前端后，再分阶段删除或瘦身

## 推荐下一步

如果继续沿当前路线推进，最自然的下一步是：

1. 在 `game_core` 实现权威 `DialogueRuntimeState`
2. 在 `game_core` 实现真实地图切换
3. 在 `bevy_server` 补本地 TCP transport
4. 再把 Godot 改成只消费协议的表现层客户端

这样可以继续保持：

- `逻辑` 在 Rust / Bevy
- `表现` 在 Godot
- `编辑` 在独立工具

也最符合仓库当前的三端分离目标。
