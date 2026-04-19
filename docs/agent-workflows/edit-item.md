# Edit Item Workflow

## Scope

适用于：

- 修改现有 item 定义
- 新增 item
- 调整 item 属性、片段、掉落相关字段

## Primary Files

- `data/items/*.json`

常见依赖：

- `data/recipes/*.json`
- `data/characters/*.json`
- `data/json/effects/*`

## Agent Steps

1. 定位目标 item 文件；若不存在，先确认新建文件名和目标 id。
2. 先读取 item 摘要，再检查是否被 recipe、角色掉落、地图拾取或其他 item 片段引用。
3. 修改 JSON。
4. 跑最小校验。
5. 总结变更影响面。

## Validation

当前优先使用：

- `cargo run -p content_tools -- locate item <id>`
- `cargo run -p content_tools -- summarize item <id>`
- `cargo run -p content_tools -- references item <id>`
- `cargo run -p content_tools -- format item <id>`
- `cargo run -p content_tools -- validate item <id>`

保底编译基线：

- `cargo check -p bevy_item_editor -p content_tools`

## Output Expectations

- 修改了哪些字段
- 是否新增或变更 id
- 是否存在引用联动风险
- 是否需要再进入 editor 复核模型/预览
