# CDC 末日生存 - Telegram WebApp 集成

## 概述

CDC 末日生存游戏已集成 Telegram WebApp 支持，可以在 Telegram 内置浏览器中全屏、沉浸式运行。

## 完成的功能

### 1. ✅ HTML 优化 (`export/web/index.html`)

- **Telegram WebApp SDK** - 引入 https://telegram.org/js/telegram-web-app.js
- **全屏模式** - 自动调用 `Telegram.WebApp.expand()`
- **主题适配** - 根据 `Telegram.WebApp.colorScheme` 自动设置深色/浅色模式
- **安全区域适配** - 使用 `env(safe-area-inset-*)` 处理底部手势条
- **事件监听** - 主题变化、视口变化自动响应

### 2. ✅ JavaScript 桥梁 (`export/web/telegram_webapp_bridge.js`)

提供以下接口供 Godot 调用：

```javascript
// UI 控制
window.godotTelegramBridge.showMainButton(text)
window.godotTelegramBridge.hideMainButton()
window.godotTelegramBridge.setMainButtonLoading(true/false)

// 震动反馈
window.godotTelegramBridge.hapticFeedback('light'|'medium'|'heavy'|'success'|'error'|'warning')

// 弹窗
window.godotTelegramBridge.showPopup(title, message, buttons)
window.godotTelegramBridge.showAlert(message)
window.godotTelegramBridge.showConfirm(message)

// 获取信息
window.godotTelegramBridge.getInitData()
window.godotTelegramBridge.getUserInfo()
window.godotTelegramBridge.getThemeParams()
window.godotTelegramBridge.getColorScheme()

// 其他
window.godotTelegramBridge.openLink(url)
window.godotTelegramBridge.close()
window.godotTelegramBridge.sendData(data)
```

### 3. ✅ Godot 集成脚本 (`scripts/telegram_integration.gd`)

**单例名称**: `TelegramIntegration`

**主要功能**:

```gdscript
# 检测环境
if TelegramIntegration.is_telegram_webapp():
    print("在 Telegram 中运行")

# 主按钮控制
TelegramIntegration.show_main_button("保存游戏")
TelegramIntegration.hide_main_button()
TelegramIntegration.set_main_button_loading(true)

# 震动反馈
TelegramIntegration.haptic_feedback("light")
TelegramIntegration.play_success_feedback()
TelegramIntegration.play_error_feedback()

# 弹窗
TelegramIntegration.show_popup("标题", "消息内容")
TelegramIntegration.show_alert("警告信息")
TelegramIntegration.show_confirm("确认删除？")

# 获取用户信息
var user_info = TelegramIntegration.get_user_info()
var user_id = user_info.get("id", 0)
var username = user_info.get("username", "")

# 云存档（发送数据到 Bot）
TelegramIntegration.save_game_to_cloud(save_data)
```

**信号**:
- `theme_changed(color_scheme)` - 主题变化
- `viewport_changed()` - 视口变化
- `main_button_pressed()` - 主按钮按下
- `window_resized(new_size)` - 窗口大小变化

### 4. ✅ 项目配置 (`project.godot`)

已添加 AutoLoad:
```
TelegramIntegration="*res://scripts/telegram_integration.gd"
```

## 部署步骤

### 1. 上传文件到 COS

使用提供的 PowerShell 脚本：

```powershell
# 设置执行策略（首次运行需要）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 运行上传脚本
.\tools\upload_telegram_webapp.ps1 -Force
```

或者手动上传以下文件：
- `export/web/index.html`
- `export/web/index.js`
- `export/web/index.wasm`
- `export/web/index.pck`
- `export/web/index.png`
- `export/web/telegram_webapp_bridge.js`
- `export/web/index.audio.worklet.js`
- `export/web/index.audio.position.worklet.js`

### 2. 配置 Telegram Bot

1. 打开 [@BotFather](https://t.me/botfather)
2. 发送 `/mybots`
3. 选择你的 Bot
4. 选择 **Bot Settings**
5. 选择 **Menu Button**
6. 选择 **Configure menu button**
7. 输入游戏链接：
   ```
   https://your-bucket.cos.ap-guangzhou.myqcloud.com/telegram-webapp/index.html
   ```

### 3. 设置 WebApp 权限

在 [@BotFather](https://t.me/botfather) 中：
1. 选择 **Bot Settings**
2. 选择 **Web App**
3. 确保 WebApp 已启用

## 使用示例

### 在游戏脚本中使用

```gdscript
extends Control

func _ready():
    # 检查是否在 Telegram 中
    if TelegramIntegration.is_telegram_webapp():
        # 设置主按钮
        TelegramIntegration.show_main_button("开始游戏")
        TelegramIntegration.main_button_pressed.connect(_on_main_button_pressed)
        
        # 播放震动
        TelegramIntegration.play_button_feedback()
        
        # 监听主题变化
        TelegramIntegration.theme_changed.connect(_on_theme_changed)
    else:
        # 非 Telegram 环境，显示普通按钮
        $StartButton.show()

func _on_main_button_pressed():
    start_game()

func _on_theme_changed(scheme):
    if scheme == "dark":
        # 切换到深色主题
        pass
    else:
        # 切换到浅色主题
        pass

func start_game():
    TelegramIntegration.haptic_feedback("medium")
    get_tree().change_scene_to_file("res://scenes/game.tscn")
```

### 保存游戏到云端

```gdscript
func save_game():
    var save_data = {
        "player_name": player_name,
        "level": current_level,
        "inventory": inventory_data,
        "timestamp": Time.get_unix_time_from_system()
    }
    
    TelegramIntegration.save_game_to_cloud(save_data)
    TelegramIntegration.show_alert("游戏已保存！")
```

## 测试

### 本地测试

1. 启动本地服务器：
   ```bash
   cd export/web
   python -m http.server 8080
   ```

2. 在浏览器中访问：
   ```
   http://localhost:8080/index.html
   ```

### Telegram 测试

1. 在 Telegram 中打开 Bot
2. 点击菜单按钮（Menu Button）
3. 游戏将在 Telegram 内置浏览器中启动

## 注意事项

1. **HTTPS 必需** - Telegram WebApp 要求必须使用 HTTPS
2. **文件大小** - WASM 文件较大 (~37MB)，首次加载需要等待
3. **横屏推荐** - 游戏设计为横屏，竖屏会显示提示
4. **内存限制** - Telegram WebView 有内存限制，避免加载过多资源

## 文件结构

```
export/web/
├── index.html                    # 主 HTML（已集成 Telegram SDK）
├── telegram_webapp_bridge.js     # JS-Godot 通信桥梁
├── index.js                      # Godot Web 引擎
├── index.wasm                    # Godot WebAssembly
├── index.pck                     # 游戏资源包
└── ...

scripts/
└── telegram_integration.gd       # Godot Telegram 集成脚本

tools/
├── custom_html_shell.html        # 自定义 HTML 模板
└── upload_telegram_webapp.ps1    # COS 上传脚本
```

## 参考链接

- [Telegram WebApp API](https://core.telegram.org/bots/webapps)
- [Godot Web Export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [腾讯云 COS](https://cloud.tencent.com/document/product/436)

---

完成时间: 2026-02-20
