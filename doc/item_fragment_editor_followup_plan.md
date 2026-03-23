# Item Fragment Editor Follow-up Plan

## Summary

本计划承接当前已经完成的 `Rust + Tauri` 物品 fragment 化重构，目标是在不改变共享 `Rust` 权威 schema 方向的前提下，把编辑器从“结构已正确”推进到“内容制作高效、可维护、可持续扩展”。

当前基础已经具备：

- 共享 `Rust` 物品模型已切换为 `ItemDefinition + Vec<ItemFragment>`
- `data/items/*.json` 已迁移到 fragment schema
- effect 引用已通过共享 `Rust` 数据层建模与校验
- `tools/tauri_editor` 已切到 fragment-driven item editor
- item / effect / item amount 的高频编辑已有基础 picker 体验

下一阶段重点不是再次推翻 schema，而是在现有模型上补齐：

- 引用预览与反查
- 字段级校验反馈
- 模板化与批量化内容制作
- registry / catalog 收紧
- 数据质量 lint 与报告能力

## Goals

1. 让内容作者在 fragment 编辑场景下更快理解引用对象，减少来回跳转和记忆负担。
2. 让校验结果尽量落到具体 fragment 字段，减少“知道有错但不知道在哪改”的体验损耗。
3. 让高频物品创建流程从“空白开始组装”升级为“模板 + 复制 + 微调”。
4. 继续把可共享的数据约束下沉到 `Rust` 层，避免编辑器端长期维护另一套规则。
5. 在不破坏当前 fragment 扩展性的前提下，逐步减少字符串漂移和脏数据累积。

## Workstreams

### 1. Reference Preview

为 item editor 中的 item / effect 引用增加详情预览能力。

范围：

- effect badge / picker 可直接预览：
  - `id`
  - `name`
  - `description`
  - `category`
  - `duration`
  - `stack_mode`
  - `gameplay_effect.resource_deltas`
- item 引用可直接预览：
  - `id`
  - `name`
  - `value`
  - `weight`
  - 推导标签
  - 关键 fragments 摘要

建议实现：

- Tauri host 新增轻量引用详情 payload 或 workspace 内预加载摘要索引
- 前端支持：
  - hover 预览
  - 点击右侧 detail panel
  - 在 fragment 卡片中保留当前 badge 式摘要

收益：

- 修理材料、配方、装备效果、可使用效果编辑效率显著提升
- 减少错误引用与误选

### 2. Field-level Validation Mapping

把共享 `Rust` validator 的错误更细地映射到具体字段和 fragment。

目标：

- 不只在 validation panel 中显示“文档有问题”
- 要让用户在编辑位点上知道错误落在哪个字段

优先覆盖：

- `equip.slots`
- `equip.equip_effect_ids`
- `equip.unequip_effect_ids`
- `weapon.ammo_type`
- `weapon.on_hit_effect_ids`
- `usable.effect_ids`
- `crafting.crafting_recipe.materials`
- `crafting.deconstruct_yield`
- `durability.repair_materials`

建议实现：

- `ValidationIssue` 增加更稳定的 `path` 约定
- 共享 `Rust` 层输出更明确的字段路径
- 前端字段组件支持 error / warning state
- validation panel 保留为全局汇总，而不是唯一入口

### 3. Template and Duplication Workflow

提升高频物品创建效率。

建议新增：

- `New From Template`
- `Duplicate Current Item`
- `Clone Fragment Set`

建议模板：

- 基础材料
- 可堆叠消耗品
- 近战武器
- 远程武器
- 护甲
- 饰品
- 带配方材料

复制规则建议：

- 自动生成新 `id`
- 默认重命名为 `原名称 Copy`
- 保留 fragments
- 保留 effect / crafting / repair 引用

### 4. Shared Registries / Catalog Tightening

逐步收紧目前仍是自由字符串的高频字段，减少内容漂移。

优先项：

- equipment slots
- rarity
- weapon subtype
- usable subtype

原则：

- 继续以共享 `Rust` 层为权威来源
- 不强行一次性把所有字符串都变成枚举
- 优先收紧高频、稳定、需要搜索和统计的字段

建议路线：

1. 先做共享 registry + catalog
2. 编辑器默认从 registry 选
3. 校验器对未知值报 warning
4. 稳定后再考虑升级为更强类型

### 5. Data Lint and Reporting

在共享 `Rust` 层补一批面向内容质量的 lint，而不只是 schema 合法性校验。

建议 lint：

- 没有任何 item 引用的 effect
- 没有 icon 的 item
- 没有 economy fragment 的 item
- 可装备 item 没有属性加成也没有效果
- effect 为 placeholder 且长期未补真实 payload
- 过度重复的 item 组合，提示可以模板化

编辑器建议增加一个只读报告页：

- Items report
- Effects report
- Broken references
- Unused content

### 6. Reverse Reference Inspection

新增引用反查能力。

需要支持：

- 某个 effect 被哪些 items / 哪些 fragments 引用
- 某个 item 被哪些 recipe / repair / ammo_type / deconstruct 使用

建议形式：

- 右侧详情面板增加 `Used By`
- 支持从 badge / picker 直接跳转

收益：

- 修改 effect 或材料定义时更安全
- 批量重构和内容清理更可控

### 7. Searchable Pickers

当前 picker 已经比纯文本好很多，但 catalog 增长后仍会遇到可用性问题。

后续建议：

- item picker 支持模糊搜索
- effect picker 支持模糊搜索
- 支持按推导标签或 fragment kind 过滤
- 长列表改为 searchable combobox，而不是原生 select

### 8. Fragment Header Quick Edit

在已有 fragment 摘要基础上，给高频字段增加“卡片头部快速编辑”。

优先候选：

- `economy.rarity`
- `stacking.max_stack`
- `equip.level_requirement`
- `usable.use_time`
- `weapon.damage`

目标：

- 常见改动不必展开整个 fragment
- 保持卡片式 authoring 节奏

### 9. Frontend Tests for Item Authoring

补齐 item editor 相关测试，降低后续持续打磨 UI 时的回归风险。

至少覆盖：

- 新建 item 并添加 `equip + usable`
- 保存后重载字段不丢失
- 删除 fragment 后 UI 状态与 validation 同步
- effect/item picker 写回真实 id 而不是 label
- fragment 摘要在关键字段更新后同步刷新

### 10. Workspace / Host Integration Tests

在 Tauri host 或共享 Rust 层补充更靠近真实 workspace 的验证。

建议覆盖：

- `load_item_workspace` 正确带出 `effectEntries`
- save 时按最终 item 集合做交叉引用校验
- effect / item 引用错误能稳定映射到前端 issue

## Recommended Execution Order

建议按下面顺序推进：

1. Reference Preview
2. Field-level Validation Mapping
3. Template and Duplication Workflow
4. Reverse Reference Inspection
5. Searchable Pickers
6. Data Lint and Reporting
7. Registry / Catalog Tightening
8. Fragment Header Quick Edit

原因：

- 前三项最直接提升日常内容制作效率
- 反查和搜索解决规模增长后的编辑复杂度
- lint / registry 收紧更适合在基础体验稳定后推进

## Non-goals

本计划默认不在这一阶段处理：

- Godot 编辑器兼容层回补
- 开放字符串自定义 fragment 机制
- item schema 再次大幅推翻
- 把护甲额外拆成独立 `armor` fragment
- 把编辑器变成运行时逻辑宿主

## Milestone Suggestion

### Milestone A: Authoring Usability

- 引用预览
- 字段级校验
- 模板化新建
- 复制当前物品

### Milestone B: Large Catalog Ergonomics

- 引用反查
- 可搜索 picker
- fragment 头部快速编辑

### Milestone C: Data Quality and Governance

- lint / report 页面
- registry 收紧
- 更多 workspace integration tests

## Success Criteria

达到以下状态即可认为这一阶段完成：

- 内容作者可以在 editor 内独立完成常见 item 新建、复制、配方和效果配置
- 常见引用错误无需离开当前字段即可定位
- 中等规模 item/effect catalog 下仍能快速搜索和编辑
- 共享 `Rust` 层仍然是 item/effect 校验与 schema 演进的唯一权威来源
- 这套改动不会增加对 Godot 运行时表现层的新耦合
