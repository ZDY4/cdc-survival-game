# CDC Survival Game 可玩化路线图

## 文档目的

本路线图用于回答两个问题：

1. 这个项目距离“真正能玩起来”还差哪些关键环节。
2. 这些环节应该按什么顺序推进，才能尽快得到一个稳定、可迭代的 playable build。

本文件只负责阶段顺序、依赖关系和优先级，不展开到具体实现细节。具体执行拆到同目录下的子 plan。

## 当前判断

仓库已经具备一批关键基础能力：

- `rust/crates/game_data` 已承担角色、地图、物品、技能、任务、配方、对话、商店、聚落、overworld 等共享 schema、加载与校验。
- `rust/crates/game_core` 已具备移动、交互、战斗、掉落、任务推进、地图切换、存档快照等核心运行时能力。
- `rust/crates/game_bevy` 已承担 runtime 内容装配、世界渲染、角色预览、UI snapshot、NPC life 集成。
- `rust/apps/bevy_debug_viewer` 已具备主菜单、新游戏、继续游戏、背包、技能、制作、交易、容器、地图 UI 和交互输入。
- `data/` 下已经有第一批可消费内容：
  - `characters`: 11
  - `maps`: 12
  - `items`: 125
  - `skills`: 13
  - `quests`: 6
  - `recipes`: 30
  - `shops`: 1
  - `dialogues`: 7
  - `settlements`: 1
  - `overworld`: 1

当前主要缺口不是底层系统，而是“玩家闭环”：

- 新游戏后缺少明确的首个 10-20 分钟任务驱动。
- 任务系统存在，但与新游戏入口、对话内容、可完成目标之间的挂接不完整。
- 玩家失败、恢复、回据点、重新出发的产品级流程还未收口。
- `bevy_debug_viewer` 仍偏开发工具气质，没有完全收口成玩家端。
- 视觉、音频、反馈仍大量依赖 placeholder。

## 目标阶段

### Phase 0: 得到第一版可玩闭环

目标：

- 玩家从主菜单进入游戏。
- 明确获得第一个任务。
- 完成一次“出据点 -> 搜刮或战斗 -> 回据点 -> 交付 -> 得奖励/解锁”的闭环。
- 有最小失败恢复逻辑。

依赖子计划：

- [01_new_game_first_15min.md](G:/Projects/cdc_survival_game/docs/plans/01_new_game_first_15min.md)
- [02_quest_dialogue_progression.md](G:/Projects/cdc_survival_game/docs/plans/02_quest_dialogue_progression.md)
- [03_exploration_combat_loot.md](G:/Projects/cdc_survival_game/docs/plans/03_exploration_combat_loot.md)
- [04_outpost_and_economy.md](G:/Projects/cdc_survival_game/docs/plans/04_outpost_and_economy.md)

### Phase 1: 把调试入口收口成玩家入口

目标：

- 用现有 runtime 保留开发便利，但将玩家默认体验与调试体验分层。
- 去掉阻碍玩家理解的 debug 噪音。
- 确保新游戏、继续游戏、暂停、失败恢复、状态提示是完整产品路径。

依赖子计划：

- [05_player_client_cleanup.md](G:/Projects/cdc_survival_game/docs/plans/05_player_client_cleanup.md)

### Phase 2: 扩展第二轮内容和生产能力

目标：

- 在首个闭环稳定后，再增加第二个地点、第二段任务链、更多对话和资源循环。
- 把内容扩展流程沉淀为稳定生产管线，不让新增内容继续依赖手工散落修改。

依赖子计划：

- [06_content_pipeline_and_editors.md](G:/Projects/cdc_survival_game/docs/plans/06_content_pipeline_and_editors.md)

### Phase 3: 进入表现与留存优化

目标：

- 替换关键 placeholder 表现。
- 增加音频和反馈。
- 对前 20 分钟体验做 polish。

依赖子计划：

- [07_presentation_audio_polish.md](G:/Projects/cdc_survival_game/docs/plans/07_presentation_audio_polish.md)

## 当前优先级排序

1. 首个 15 分钟闭环是否成立。
2. 任务是否可发放、可推进、可交付、可奖励。
3. 玩家失败后是否还能继续玩，而不是只剩 runtime 事件。
4. 据点是否能承担“补给、交易、制作、再出发”的中心节点职责。
5. 玩家端 UI/流程是否从 debug 工具气质中抽离。
6. 内容生产是否可以低摩擦扩展。
7. 视觉、音频和反馈是否足够支撑第二次游玩。

## 推荐近期里程碑

### M1: 首个可完成任务上线

- 新游戏后能稳定进入据点外场。
- 玩家能获得并完成 1 个任务。
- 任务完成后给予明确奖励和提示。

### M2: 首个风险回路上线

- 玩家在外场能搜刮、战斗、回收。
- 玩家死亡或失败后有明确恢复路径。
- 存档与恢复不破坏主循环。

### M3: 首个稳定 playable build

- 新玩家在不了解 debug 背景的情况下，也能完成前 10-20 分钟。
- 主循环不依赖控制台命令或开发者知识。

## 近期冲刺拆分

### Sprint A: 让第一个任务真的能开始

目标：

- 新游戏后 30 秒内出现明确第一目标。
- 首任务不再依赖当前未接通的 `sleep` 目标。

交付：

- 新游戏默认状态收口。
- 首任务定义调整完成。
- 首次任务发放路径固定。

依赖子计划：

- [01_new_game_first_15min.md](G:/Projects/cdc_survival_game/docs/plans/01_new_game_first_15min.md)
- [02_quest_dialogue_progression.md](G:/Projects/cdc_survival_game/docs/plans/02_quest_dialogue_progression.md)

### Sprint B: 让第一个任务真的能完成

目标：

- 玩家能去一张外场图完成任务。
- 任务完成后能回据点交付，得到奖励和下一步驱动。

交付：

- 外场收益和风险收口。
- 任务推进和回报跑通。
- 据点交付和消费场景接通。

依赖子计划：

- [03_exploration_combat_loot.md](G:/Projects/cdc_survival_game/docs/plans/03_exploration_combat_loot.md)
- [04_outpost_and_economy.md](G:/Projects/cdc_survival_game/docs/plans/04_outpost_and_economy.md)

### Sprint C: 让第一次失败不至于结束体验

目标：

- 玩家首次失败后能继续当前 build，不需要开发者命令恢复。

交付：

- 最小失败恢复逻辑。
- 玩家主流程 UI 收口。

依赖子计划：

- [04_outpost_and_economy.md](G:/Projects/cdc_survival_game/docs/plans/04_outpost_and_economy.md)
- [05_player_client_cleanup.md](G:/Projects/cdc_survival_game/docs/plans/05_player_client_cleanup.md)

## 本轮执行规则

- 优先做“把现有系统串起来”，而不是继续扩系统广度。
- 先把任务、对话、奖励、失败恢复闭环跑通，再扩更多地图和系统。
- 编辑器方向以服务内容生产为目标，不反向定义 runtime 权威。
- 只保留一套长期实现，不为过渡方案留双写和镜像逻辑。

## 可执行 TODO

### Now

- [ ] 将首个教程任务从 `sleep` 导向改为 runtime 已支持的目标组合。
- [ ] 固定首个任务发放入口，只保留一个权威入口。
- [ ] 缩减新游戏默认已解锁地点，避免开局失焦。
- [ ] 选定首张教学外场和首张资源外场。

### Next

- [ ] 接通任务交付、奖励和下一步驱动。
- [ ] 明确玩家失败后的最小恢复方案。
- [ ] 收口 `bevy_debug_viewer` 的玩家默认界面。

### Later

- [ ] 扩展第二段任务链和第二轮地点内容。
- [ ] 为内容扩展建立稳定“内容包”生产方式。
- [ ] 开始替换高频 placeholder 与补反馈。

## 本轮建议完成定义

当以下条件同时成立时，可认为当前路线图的近期目标达成：

- 新游戏后首任务能稳定开始。
- 首任务能稳定推进和完成。
- 玩家完成第一次外出和回据点交付。
- 即使首次失败，玩家也有继续路径。
- 主循环不依赖控制台和内部调试面板。

## 近期建议阅读顺序

1. [01_new_game_first_15min.md](G:/Projects/cdc_survival_game/docs/plans/01_new_game_first_15min.md)
2. [02_quest_dialogue_progression.md](G:/Projects/cdc_survival_game/docs/plans/02_quest_dialogue_progression.md)
3. [03_exploration_combat_loot.md](G:/Projects/cdc_survival_game/docs/plans/03_exploration_combat_loot.md)
4. [04_outpost_and_economy.md](G:/Projects/cdc_survival_game/docs/plans/04_outpost_and_economy.md)
5. [05_player_client_cleanup.md](G:/Projects/cdc_survival_game/docs/plans/05_player_client_cleanup.md)
6. [06_content_pipeline_and_editors.md](G:/Projects/cdc_survival_game/docs/plans/06_content_pipeline_and_editors.md)
7. [07_presentation_audio_polish.md](G:/Projects/cdc_survival_game/docs/plans/07_presentation_audio_polish.md)
