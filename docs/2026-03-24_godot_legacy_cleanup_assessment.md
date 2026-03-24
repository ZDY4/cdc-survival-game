# 2026-03-24 Godot Legacy Cleanup Assessment

本文件基于 2026-03-24 当天已经完成的 Rust / Bevy headless 逻辑迁移，评估：

- Godot 中哪些旧脚本已经不该继续承载规则
- 哪些脚本现在可以开始瘦身
- 哪些脚本暂时还不能直接删除
- 后续应按什么顺序清理

本文不是“立即删除清单”，而是**分阶段退役评估**。

## 1. 评估前提

截至当前仓库状态，Rust 侧已经收权的能力包括：

- 网格 / 阻挡 / 寻路 / 自动移动
- 回合 / AP
- 基础交互执行框架
- 战斗距离、伤害、HP、击杀
- 掉落生成
- XP / 升级 / 点数发放
- headless economy
  - 背包
  - 装备
  - 装填
  - 耐久
  - 技能学习
  - 制作
  - 商店买卖
- 最小 quest runtime
  - `kill`
  - `collect`
  - `start -> objective -> reward -> end`

因此，Godot 中凡是继续持有这些域的权威规则逻辑，都已经属于 legacy 候选。

但同时，Rust 侧还没有完全收完这些关键域：

- 权威 `save / load snapshot`
- 完整 `dialogue runtime`
- 完整 `map travel / scene context runtime`
- 正式长期运行的 `bevy_server` transport / protocol host

这意味着：**Godot 旧脚本可以开始退役，但还不适合今天就做一次性大删除。**

## 2. 清理原则

### 2.1 现在就该停止的事

- 不再往 Godot 旧运行时脚本里新增长期规则
- 不再在 Godot 中扩张回合、战斗、任务、经济、AI 权威实现
- 不再把“未来属于 Rust 的逻辑”临时堆回 GDScript

### 2.2 当前正确的清理方式

每个 legacy 域都按同一个顺序清理：

1. 先标记为 legacy
2. 先瘦身成兼容壳
3. 再替换调用点
4. 最后删除实现文件

### 2.3 当前不建议做的事

- 不要按文件夹做一次性大扫除
- 不要在 Rust 侧还没补齐前就删除 Godot 唯一可运行路径
- 不要把“表现层脚本”和“规则脚本”一起粗暴删除

## 3. 脚本分级

## A 级：现在就可以开始瘦身，且应明确标记 legacy

这些脚本所在的规则域，已经有相当一部分 Rust 权威承接面。

### [systems/turn_system.gd](/D:/Projects/cdc-survival-game/systems/turn_system.gd)

判断：

- Godot 本地 AP / turn 权威已经不应继续扩张
- 该脚本可以开始退役为兼容壳

建议动作：

- 标记 legacy
- 停止新增规则逻辑
- 把还能保留的内容收缩为：
  - 前端输入转发
  - UI 通知
  - 调试展示桥接

删除前置条件：

- Godot 输入已改成走 Rust/协议驱动回合

### [systems/combat_system.gd](/D:/Projects/cdc-survival-game/systems/combat_system.gd)

判断：

- 战斗结算主体已经明显属于 Rust 侧
- Godot 本地伤害、击杀、掉落、升级结算应视为 legacy

建议动作：

- 标记 legacy
- 删除或下沉重复的数值结算 helper
- 保留：
  - 表现回调
  - 动画/音效触发
  - 前端命中反馈桥接

删除前置条件：

- Godot 只消费 Rust 战斗结果

### [systems/interaction_system.gd](/D:/Projects/cdc-survival-game/systems/interaction_system.gd)

判断：

- 当前最适合变成协议前端壳
- 不应继续在这里新增本地权威交互判断和执行逻辑

建议动作：

- 标记 legacy
- 把其职责收敛为：
  - 点击命中
  - prompt 请求
  - option 展示
  - 命令发送
  - 结果消费

删除前置条件：

- Rust 侧 dialogue / map travel / protocol 已补齐

### [modules/interaction/options/interaction_option.gd](/D:/Projects/cdc-survival-game/modules/interaction/options/interaction_option.gd)

判断：

- 若其中仍含规则可执行性判断或执行路径，已经属于 legacy

建议动作：

- 仅保留 UI / 前端显示语义
- 将规则判断迁回 Rust 权威

删除前置条件：

- Godot option 仅消费协议 payload

## B 级：现在可以做边界整理，但不建议直接删

这些脚本多半混合了“规则 + 客户端状态 + 场景协调”，短期内仍会被现有前端依赖。

### [core/game_state.gd](/D:/Projects/cdc-survival-game/core/game_state.gd)

判断：

- 这是最典型的 Godot 侧权威状态容器 legacy 候选
- 但它往往同时承担前端缓存和场景共享状态

建议动作：

- 先拆分概念边界：
  - Rust 权威世界状态
  - Godot 本地只读缓存
  - UI 临时状态
- 先删除“本地结算”职责
- 暂不直接删文件

删除前置条件：

- runtime snapshot / delta / save-load 已稳定

### [modules/map/map_module.gd](/D:/Projects/cdc-survival-game/modules/map/map_module.gd)

判断：

- 其中如果还包含旅行规则、返回点规则、场景上下文规则，已经是 legacy
- 但场景切换编排本身仍可能长期保留在 Godot

建议动作：

- 先把“规则部分”和“场景加载部分”拆开
- 保留：
  - 场景加载
  - 相机定位
  - 表现切换
- 迁出：
  - 旅行判定
  - 上下文切换规则
  - 返回点逻辑

删除前置条件：

- Rust 权威 map travel / scene context runtime 完成

### [systems/ai/ai_manager.gd](/D:/Projects/cdc-survival-game/systems/ai/ai_manager.gd)

判断：

- 决策、敌友判断、行为拼装中的规则部分应视为 legacy
- 但视觉节点装配和点击映射可能仍会保留

建议动作：

- 先把 AI 决策循环和规则判断剥离
- 保留：
  - visual actor spawn
  - 表现桥接
  - actor id 映射

删除前置条件：

- Rust AI 状态可以完整驱动前端 actor 表现

### [core/data_manager.gd](/D:/Projects/cdc-survival-game/core/data_manager.gd)

判断：

- 共享 schema、加载、校验逻辑长期不应再由 Godot 权威维护
- 但当前仓库里它可能还兼带运行期资源装配和前端便利加载

建议动作：

- 先标记“共享内容定义和校验已迁移目标为 Rust”
- 逐步移除：
  - schema 权威
  - cross-reference 校验
  - 规则相关迁移逻辑
- 暂不直接删整个文件

删除前置条件：

- Rust 内容加载 / 校验 / workspace 存取路径完全稳定

## C 级：当前不建议按“删除 legacy 文件”思路处理

这些部分更像前端壳或表现层，不应因为规则迁移就一并删除。

### Godot 场景 / UI / 输入 / 相机 / 动画 / 音频 / VFX

判断：

- 这些不属于“旧规则脚本”，而是表现层
- 即使最终完全走 Rust 权威，它们仍然会保留

建议动作：

- 不纳入本轮 legacy 删除范围

### Godot 编辑器专属工具

例如：

- `addons/cdc_procedural_builder`
- Inspector / Dock 集成

判断：

- 这些依赖 Godot 编辑器能力，不应因为运行时迁移就误删

建议动作：

- 不纳入当前 runtime legacy 清理范围

## 4. 建议的近期清理顺序

如果目标是“在不打断当前客户端的前提下，逐步减少 Godot legacy 权威逻辑”，推荐顺序如下：

1. 先处理 [systems/turn_system.gd](/D:/Projects/cdc-survival-game/systems/turn_system.gd)
2. 再处理 [systems/combat_system.gd](/D:/Projects/cdc-survival-game/systems/combat_system.gd)
3. 再处理 [systems/interaction_system.gd](/D:/Projects/cdc-survival-game/systems/interaction_system.gd)
4. 再处理 [modules/interaction/options/interaction_option.gd](/D:/Projects/cdc-survival-game/modules/interaction/options/interaction_option.gd)
5. 然后整理 [core/game_state.gd](/D:/Projects/cdc-survival-game/core/game_state.gd)
6. 再整理 [modules/map/map_module.gd](/D:/Projects/cdc-survival-game/modules/map/map_module.gd)
7. 最后整理 [systems/ai/ai_manager.gd](/D:/Projects/cdc-survival-game/systems/ai/ai_manager.gd) 和 [core/data_manager.gd](/D:/Projects/cdc-survival-game/core/data_manager.gd)

原因：

- 前四项是当前最明确属于 Rust 权威目标的规则域
- 后三项混合职责更多，需要等 Rust 侧再补几块关键能力后再下重手

## 5. 当前可以立即执行的低风险动作

这些动作现在就可以做，且风险相对低：

- 给上述 legacy 候选脚本补清晰注释，明确“不再新增长期规则逻辑”
- 删除已经明显重复的 Godot 本地规则 helper
- 把本地结算函数改名为 `legacy_*` 或集中到 compatibility 区域
- 在调用点层面，优先改成：
  - 请求 Rust
  - 消费结果
  - 更新 UI / 表现

## 6. 当前不应该误判为“可以直接删除”的原因

虽然今天 Rust 迁移已经推进很多，但以下能力还没完全闭环：

- 存档
- 对话运行时
- 地图旅行与上下文切换
- 稳定 protocol host

所以现在对 Godot legacy 的正确结论是：

- 可以开始清理
- 可以开始退役
- 可以开始瘦身
- 但还不适合一次性大量直接删文件

## 7. 最终结论

今天的逻辑迁移之后，Godot 中很多旧脚本**已经可以被正式认定为 legacy 域**，尤其是：

- [systems/turn_system.gd](/D:/Projects/cdc-survival-game/systems/turn_system.gd)
- [systems/combat_system.gd](/D:/Projects/cdc-survival-game/systems/combat_system.gd)
- [systems/interaction_system.gd](/D:/Projects/cdc-survival-game/systems/interaction_system.gd)
- [modules/interaction/options/interaction_option.gd](/D:/Projects/cdc-survival-game/modules/interaction/options/interaction_option.gd)

但当前更合理的做法是：

- 先停止扩张
- 先改成兼容壳
- 先拆掉权威规则职责
- 等 Rust 补完剩余闭环后，再删实现文件

如果当前目标仍然是“先完全脱离 Godot，在 Bevy 中把完整逻辑跑通”，那么 Godot legacy 清理的优先级应排在：

- runtime command surface
- save/load snapshot
- dialogue runtime
- map travel runtime

之后，而不是反过来先做 Godot 大清理。
