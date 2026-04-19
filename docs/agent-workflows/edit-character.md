# Edit Character Workflow

## Scope

适用于：

- 修改现有角色定义
- 新增角色
- 调整角色属性、掉落、阵营、展示、调度等数据

## Primary Files

- `data/characters/*.json`

常见依赖：

- `data/appearance/characters/*.json`
- `data/dialogues/*.json`
- `data/maps/*.json`

## Agent Steps

1. 定位目标 character 文件。
2. 先读取角色摘要，再检查相关 appearance / dialogue / map 引用。
3. 修改 JSON。
4. 跑最小校验。
5. 若涉及外观或空间摆放，提示进入 editor / viewer 复核。

## Validation

当前优先使用：

- `cargo run -p content_tools -- locate character <id>`
- `cargo run -p content_tools -- summarize character <id>`
- `cargo run -p content_tools -- format character <id>`
- `cargo run -p content_tools -- validate character <id>`

保底编译基线：

- `cargo check -p content_tools`

如需进入 editor 复核或手工精修：

- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Character <id>`

## Output Expectations

- 修改了哪些角色字段
- 是否影响 appearance / dialogue / map 配置
- 是否建议再做可视化复核
