# CDC末日生存游戏 - H5版本开发文档

## 已完成的适配工作

### 1. Web导出配置
- ✅ 修改 `project.godot` 添加Web显示适配设置
  - 启用 `canvas_items` 拉伸模式
  - 设置 `aspect=expand` 支持不同屏幕比例
  - 启用GL兼容性渲染器
  - 启用ETC2/ASTC纹理压缩（移动端优化）
- ✅ 创建 `export_presets.cfg` Web导出配置
- ✅ 创建自定义HTML壳 `tools/custom_html_shell.html`
  - 移动端视口配置
  - 触摸事件优化
  - 横屏提示
  - 加载进度显示

### 2. 存档系统Web适配
- ✅ 修改 `systems/save_system.gd`
  - 检测Web平台 (`OS.has_feature("web")`)
  - Web平台使用JavaScript localStorage
  - 桌面版继续使用文件系统
  - 统一的存档数据格式

### 3. 触摸控制适配
- ✅ 创建 `core/touch_input_handler.gd`
  - 支持鼠标和触摸同时输入
  - 触摸手势识别
  - 阻止默认滚动行为
- ✅ 修改 `modules/interaction/interactable.gd`
  - 添加触摸事件处理
  - 支持触摸点击交互对象

### 4. UI响应式适配
- ✅ 创建 `core/responsive_ui_manager.gd`
  - 响应式字体大小
  - 移动端按钮放大
  - 安全区域适配
  - 滚动容器触摸支持
- ✅ 修改 `scripts/ui/main_menu.gd`
  - Web平台隐藏退出按钮
  - 安全区域适配
  - 阻止默认滚动
- ✅ 修改 `scripts/ui/inventory_ui.gd`
  - 响应式布局
  - 触摸支持

### 5. Web性能优化
- ✅ 修改 `modules/mcp/godot_mcp_bridge.gd`
  - Web平台禁用TCP服务器
- ✅ 修改 `modules/ai_test/ai_test_bridge.gd`
  - Web平台禁用HTTP服务器
- ✅ 创建 `scenes/ui/web_loading_screen.tscn`
  - Web版加载进度条
  - 游戏提示显示

### 6. 导出脚本
- ✅ 创建 `tools/export_web.py` - Python导出脚本
- ✅ 创建 `tools/export_web.bat` - Windows批处理脚本
- ✅ 创建 `tools/cos_helper.py` - 腾讯COS上传脚本

## 导出步骤

### 方法一：使用Godot编辑器导出

1. 打开Godot 4.6编辑器
2. 确保已安装Web导出模板：
   - 编辑器 -> 管理 -> 模板 -> 下载并安装
3. 项目 -> 导出 -> 添加Web预设
4. 点击"导出项目"
5. 选择导出目录：`export/web/`

### 方法二：使用命令行导出

```bash
cd G:\project\cdc_survival_game

# 使用Godot直接导出
godot --path . --export-release "Web" "export/web/index.html"
```

### 方法三：使用批处理脚本

```bash
cd G:\project\cdc_survival_game\tools
export_web.bat
```

## 本地测试

### 启动HTTP服务器

```bash
cd G:\project\cdc_survival_game\export\web

# Python 3
python -m http.server 8080

# 或使用Node.js npx
npx serve .
```

### 浏览器访问

打开浏览器访问：`http://localhost:8080`

### 测试检查清单

- [ ] 游戏能正常加载
- [ ] 主菜单显示正常
- [ ] 点击"开始游戏"进入场景
- [ ] 触摸/点击交互对象有响应
- [ ] 存档功能正常（刷新页面后数据保留）
- [ ] 读档功能正常
- [ ] 背包界面显示正常
- [ ] UI在不同屏幕尺寸下显示正常
- [ ] 浏览器控制台无错误

## 上传到腾讯COS

### 配置环境变量

```bash
set TENCENT_SECRET_ID=your-secret-id
set TENCENT_SECRET_KEY=your-secret-key
set TENCENT_COS_BUCKET=your-bucket-name
set TENCENT_COS_REGION=ap-guangzhou
```

### 运行上传脚本

```bash
cd G:\project\cdc_survival_game
python tools\cos_helper.py
```

### 手动上传

1. 登录腾讯云控制台 -> COS存储桶
2. 创建文件夹：`games/cdc-h5/`
3. 上传 `export/web/` 目录下的所有文件
4. 确保文件Content-Type正确：
   - `.html` -> `text/html`
   - `.js` -> `application/javascript`
   - `.wasm` -> `application/wasm`
   - `.pck` -> `application/octet-stream`

## 访问链接

上传完成后，访问链接格式：

```
https://{bucket-name}.cos.{region}.myqcloud.com/games/cdc-h5/index.html
```

## 已知限制

1. **文件大小限制**：Web版本总大小应控制在30MB以内
2. **浏览器兼容性**：需要支持WebGL 2.0的现代浏览器
3. **音频自动播放**：部分浏览器需要用户交互后才能播放音频
4. **本地存储限制**：localStorage有容量限制（通常5-10MB）

## 优化建议

1. 启用纹理压缩减少文件大小
2. 使用音频流式加载
3. 分割场景为多个.pck文件按需加载
4. 考虑使用Service Worker实现离线游玩

## 故障排除

### 导出失败

- 检查Godot Web导出模板是否安装
- 检查export_presets.cfg是否正确

### 游戏无法加载

- 检查浏览器是否支持WebGL 2.0
- 检查是否有CORS问题（需使用HTTP服务器）

### 触摸无响应

- 检查TouchInputHandler是否正确加载
- 检查浏览器控制台错误

### 存档失败

- Web平台需要JavaScriptBridge支持
- 检查浏览器是否禁用了localStorage
