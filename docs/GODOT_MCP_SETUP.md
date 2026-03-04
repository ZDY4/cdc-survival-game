# Godot MCP 配置

本项目已配置 Godot MCP (Model Context Protocol) 服务器，用于与 Godot 引擎交互。

## 配置文件

MCP 配置位于: `.cursor/mcp.json`

## 安装要求

1. **Node.js** >= 18.0.0
2. **Godot 4.x** 已安装
3. **godot-mcp** 位于 `D:\Projects\Tools\godot-mcp`

## 当前配置

```json
{
  "mcpServers": {
    "godot-mcp": {
      "command": "node",
      "args": ["D:\\Projects\\Tools\\godot-mcp\\build\\index.js"],
      "env": {
        "GODOT_PATH": "C:\\Program Files\\Godot\\Godot.exe",
        "GODOT_PROJECT_PATH": "D:\\Projects\\cdc-survival-game"
      }
    }
  }
}
```

## 设置 Godot 路径

### 方法 1: 修改 MCP 配置文件

编辑 `.cursor/mcp.json`，将 `GODOT_PATH` 修改为你的 Godot 安装路径：

```json
"env": {
  "GODOT_PATH": "C:\\Your\\Path\\To\\Godot.exe",
  "GODOT_PROJECT_PATH": "D:\\Projects\\cdc-survival-game"
}
```

### 方法 2: 添加到系统 PATH

将 Godot 添加到系统环境变量 PATH 中：
1. 找到 Godot 安装目录（如 `C:\Program Files\Godot`）
2. 添加到系统 PATH 环境变量
3. 重启 Cursor

### 常见 Godot 安装位置

- `C:\Program Files\Godot\Godot.exe`
- `C:\Users\<用户名>\Downloads\Godot\Godot.exe`
- Steam 安装: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.exe`

## 功能

Godot MCP 提供以下功能：

1. **启动 Godot 编辑器**
   - 打开项目
   - 运行场景

2. **项目管理**
   - 列出项目文件
   - 读取脚本内容
   - 修改脚本

3. **调试支持**
   - 捕获输出日志
   - 运行测试

## 测试连接

在 Cursor 中打开 MCP 面板，应该能看到 `godot-mcp` 服务器已连接。

## 故障排除

### 错误: "Could not find Godot"

**解决方案:**
1. 确认 Godot 已安装
2. 更新 `.cursor/mcp.json` 中的 `GODOT_PATH`
3. 或者将 Godot 添加到系统 PATH

### 错误: "node command not found"

**解决方案:**
1. 安装 Node.js >= 18.0.0
2. 确认 `node` 命令在 PATH 中

### MCP 服务器无法启动

**检查步骤:**
1. 确认 `D:\Projects\Tools\godot-mcp\build\index.js` 存在
2. 如果不存在，在 godot-mcp 目录运行 `npm run build`
3. 检查 Node.js 版本: `node --version`

## 参考

- [godot-mcp GitHub](https://github.com/Coding-Solo/godot-mcp)
- [MCP 文档](https://modelcontextprotocol.io/)
