# Edit Recipe Workflow

## Scope

适用于：

- 修改现有 recipe
- 新增 recipe
- 调整材料、产出、技能要求、解锁条件

## Primary Files

- `data/recipes/*.json`

常见依赖：

- `data/items/*.json`
- `data/skills/*.json`
- 其他 `data/recipes/*.json`

## Agent Steps

1. 定位目标 recipe 文件。
2. 先读取 recipe 摘要，再检查关联 item / skill / recipe id。
3. 修改 JSON。
4. 跑最小校验。
5. 总结是否影响现有材料或 unlock 链路。

## Validation

当前优先使用：

- `cargo run -p content_tools -- locate recipe <id>`
- `cargo run -p content_tools -- summarize recipe <id>`
- `cargo run -p content_tools -- format recipe <id>`
- `cargo run -p content_tools -- validate recipe <id>`

保底编译基线：

- `cargo check -p bevy_recipe_editor -p content_tools`

如需进入 editor 复核或手工精修：

- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Recipe <id>`

## Output Expectations

- 修改了哪些材料、产出或条件
- 是否引入新的 item / skill / recipe 依赖
- 是否需要人工复核 unlock 链路
