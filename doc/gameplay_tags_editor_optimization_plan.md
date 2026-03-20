# Gameplay Tags 编辑器优化计划

## 背景

本文整理 `Gameplay Tags` 编辑器在本次迭代中已经完成的改进，以及后续仍值得推进的优化项，方便继续排期和实现。

相关入口：

- `res://addons/gameplay_tags/editor/gameplay_tags_dock.gd`
- `res://addons/gameplay_tags/editor/gameplay_tag_inspector_plugin.gd`
- `res://addons/gameplay_tags/editor/gameplay_tag_editor_property.gd`
- `res://addons/gameplay_tags/runtime/gameplay_tags_manager.gd`
- `res://addons/gameplay_tags/plugin.gd`
- `res://systems/character_actor.gd`
- `res://config/gameplay_tags.ini`

## 本次已完成

### 菜单与入口

- 将 `Gameplay Tags` 从 `Project/Tools` 挪到了 `Editor` 菜单。
- 保留了兜底逻辑：如果找不到 `Editor` 菜单，会退回到顶部按钮。
- 插件现在会同时注册 Inspector 插件，使 GameplayTag 选择器随 addon 一起启用。

### 默认配置路径

- 默认标签配置路径改为 `res://config/gameplay_tags.ini`。
- 删除了旧的 `res://addons/gameplay_tags/config/gameplay_tags.ini`。
- 清理了旧 `addons/gameplay_tags/config` 目录。

### 编辑器可用性

- 编辑器中找不到 `GameplayTags` autoload 时，自动启用本地 manager，避免工具界面空白不可用。
- 改善了顶部状态区，显示当前数据来源、标签数量、warning 数量和最近错误。

### 界面布局

- 调整为更清晰的左右分栏布局。
- 左侧展示 Tag Library、搜索和常用操作。
- 右侧展示 Selected Tag、Warnings And Validation、Project References、Query Preview。

### 标签编辑效率

- 增加 `Add Child`。
- 增加 `Add Sibling`。
- 增加 `Expand` / `Collapse`。
- 增加右键菜单：
  - `Copy Tag Name`
  - `Add Child Tag`
  - `Add Sibling Tag`
  - `Use As Container`
  - `Use In Query`
- 增加快捷填充：
  - 将当前标签写入 Container
  - 基于当前标签生成 Query 模板
- 工具栏按钮状态化：
  - 没有选中 Tag 时，`Add Child`、`Add Sibling`、`Rename`、`Remove`、`Use As Container`、`Use In Query`、`Find References` 会自动禁用。
- 右键菜单状态化：
  - 没有选中 Tag 时，相关菜单项会自动禁用。

### 质量保护

- 新增 warnings/validation 面板。
- 保存前执行 `validate_registry()`，校验失败时阻止保存。
- 增加未保存修改提示，关闭窗口前可选择保存、放弃或取消。

### 风险预览

- 删除标签前展示将被删除的显式标签列表预览。
- 重命名前展示将被改名的显式标签数量和示例映射。
- 重命名预览中会展示关联文本引用的命中数量、文件数量和示例命中片段。
- 重命名支持两种模式：
  - `Preview Only`
  - `Auto replace matched project text references`

### 项目引用检查

- 增加 `Find References`。
- 可扫描项目中文本资源对当前 Tag 的引用。
- 引用结果现在会展示：
  - 文件路径
  - 行号
  - 命中列号
  - 命中文本片段
- 删除和重命名预览中会附带引用命中摘要，帮助判断影响范围。
- 引用匹配做了边界控制，避免把 `Status.BurningExtra` 误判为 `Status.Burning`。

### Inspector 选择器

- 新增 Inspector 内置 GameplayTag 选择器。
- 支持通过自定义导出 hint 启用：
  - `@export_custom(PROPERTY_HINT_NONE, "gameplay_tag") var tag: StringName`
  - `@export_custom(PROPERTY_HINT_NONE, "gameplay_tags") var tags: Array[StringName]`
- `StringName` 字段使用单选下拉。
- `Array[StringName]` 字段使用列表 + 添加/移除按钮。
- Inspector 控件内置 `Open Editor` 按钮，可直接打开 Gameplay Tags 编辑器。
- 已在 `CharacterActor.interaction_state_tag` 上接入一处真实用例。

### 保存反馈

- 保存成功后会展示实际写入的显式 Tag 数量和目标路径。

### 测试与文档

- 更新 `README` 默认配置路径说明。
- 更新 `README`，补充 Inspector 选择器的用法说明。
- 为默认配置路径和注册表校验新增测试覆盖。
- 为以下能力补充测试覆盖：
  - 引用命中边界
  - 文本替换边界
  - Sibling 前缀生成
  - Inspector hint 识别
  - 项目内真实字段的 Inspector opt-in

## 建议优先级

### 当前 P1：高价值，建议优先做

- 搜索增强
  - 支持只看显式标签。
  - 支持只看 warning 标签。
  - 支持按层级前缀过滤。
- 查询模板增强
  - 提供 `any_tags`、`no_tags`、`all_expr` 等模板按钮。
- 更详细的 Query 结果说明
  - 不只显示 `MATCH/NO MATCH`，还显示失败条件摘要。

### 当前 P2：中价值，建议在 P1 后推进

- `Duplicate Tag`
  - 复制当前标签并快速修改名字。
- 查询历史
  - 保存最近使用的 Query，便于反复调试。
- 配置文件外部修改检测
  - 文件被外部修改后提示重新加载。
- 引用替换流程继续增强
  - 当前已经支持文本自动替换，但仍可以继续补充更稳妥的确认、回滚和逐文件预览能力。

### P3：体验增强，可按需推进

- 树节点图标区分显式 Tag 与隐式父 Tag。
- Selected Tag 区域增加完整路径复制按钮。
- 面包屑展示当前标签层级。
- 最近使用标签列表。
- 空状态引导优化。
- 更显眼的非法节点高亮。

## 暂不需要

- CSV 导入导出。

## 下一步推荐顺序

1. 搜索增强
2. Query 模板增强
3. Query 结果失败原因说明
4. `Duplicate Tag`
5. 外部配置修改检测
