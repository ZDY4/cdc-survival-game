# Telegram WebApp 集成验证脚本
# 验证所有文件是否正确配置

param(
    [string]$ProjectPath = "G:\project\cdc_survival_game"
)

# 颜色输出函数
function Write-Success($message) {
    Write-Host "  ✓ $message" -ForegroundColor Green
}

function Write-Error($message) {
    Write-Host "  ✗ $message" -ForegroundColor Red
}

function Write-Warning($message) {
    Write-Host "  ! $message" -ForegroundColor Yellow
}

function Write-Info($message) {
    Write-Host "  → $message" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CDC 末日生存 - Telegram WebApp 验证" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true

# 1. 检查项目文件
Write-Host "[1/5] 检查项目文件..." -ForegroundColor Yellow

$requiredFiles = @{
    "index.html" = "$ProjectPath\export\web\index.html"
    "telegram_webapp_bridge.js" = "$ProjectPath\export\web\telegram_webapp_bridge.js"
    "telegram_integration.gd" = "$ProjectPath\scripts\telegram_integration.gd"
    "custom_html_shell.html" = "$ProjectPath\tools\custom_html_shell.html"
    "project.godot" = "$ProjectPath\project.godot"
}

foreach ($file in $requiredFiles.GetEnumerator()) {
    if (Test-Path $file.Value) {
        $size = (Get-Item $file.Value).Length
        $sizeStr = if ($size -gt 1KB) { "{0:N1} KB" -f ($size / 1KB) } else { "$size B" }
        Write-Success "$($file.Key) ($sizeStr)"
    } else {
        Write-Error "$($file.Key) 缺失"
        $allPassed = $false
    }
}

# 2. 检查 index.html 关键内容
Write-Host ""
Write-Host "[2/5] 检查 index.html 配置..." -ForegroundColor Yellow

$htmlContent = Get-Content "$ProjectPath\export\web\index.html" -Raw

$checks = @(
    @{ Pattern = "telegram-web-app\.js"; Desc = "Telegram SDK 引用" },
    @{ Pattern = "Telegram\.WebApp"; Desc = "WebApp 初始化代码" },
    @{ Pattern = "telegramWebAppBridge"; Desc = "Bridge 脚本引用" },
    @{ Pattern = "safe-area-inset-bottom"; Desc = "安全区域适配" },
    @{ Pattern = "expand\(\)"; Desc = "全屏模式" },
    @{ Pattern = "themeChanged"; Desc = "主题变化监听" }
)

foreach ($check in $checks) {
    if ($htmlContent -match $check.Pattern) {
        Write-Success $check.Desc
    } else {
        Write-Error $check.Desc
        $allPassed = $false
    }
}

# 3. 检查 project.godot
Write-Host ""
Write-Host "[3/5] 检查 project.godot 配置..." -ForegroundColor Yellow

$godotContent = Get-Content "$ProjectPath\project.godot" -Raw

if ($godotContent -match "TelegramIntegration") {
    Write-Success "TelegramIntegration AutoLoad 已配置"
} else {
    Write-Error "TelegramIntegration AutoLoad 未配置"
    $allPassed = $false
}

# 4. 检查导出文件完整性
Write-Host ""
Write-Host "[4/5] 检查导出文件完整性..." -ForegroundColor Yellow

$exportFiles = @(
    "index.html",
    "index.js",
    "index.wasm",
    "index.pck",
    "telegram_webapp_bridge.js"
)

$totalSize = 0
foreach ($file in $exportFiles) {
    $filePath = "$ProjectPath\export\web\$file"
    if (Test-Path $filePath) {
        $size = (Get-Item $filePath).Length
        $totalSize += $size
        Write-Success "$file"
    } else {
        Write-Error "$file 缺失"
        $allPassed = $false
    }
}

$totalSizeStr = "{0:N2} MB" -f ($totalSize / 1MB)
Write-Info "导出文件总大小: $totalSizeStr"

# 5. 检查脚本功能
Write-Host ""
Write-Host "[5/5] 检查脚本功能..." -ForegroundColor Yellow

$scriptContent = Get-Content "$ProjectPath\scripts\telegram_integration.gd" -Raw

$scriptChecks = @(
    @{ Pattern = "class_name TelegramIntegration"; Desc = "类名定义" },
    @{ Pattern = "is_telegram_webapp"; Desc = "环境检测方法" },
    @{ Pattern = "show_main_button"; Desc = "主按钮显示方法" },
    @{ Pattern = "haptic_feedback"; Desc = "震动反馈方法" },
    @{ Pattern = "save_game_to_cloud"; Desc = "云存档方法" }
)

foreach ($check in $scriptChecks) {
    if ($scriptContent -match $check.Pattern) {
        Write-Success $check.Desc
    } else {
        Write-Warning $check.Desc
    }
}

# 总结
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "✅ 验证通过！所有文件已正确配置。" -ForegroundColor Green
} else {
    Write-Host "❌ 验证失败！请检查上述错误。" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 下一步指导
Write-Host "下一步操作:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. 上传到 COS:" -ForegroundColor Cyan
Write-Host "   .\tools\upload_telegram_webapp.ps1 -Force" -ForegroundColor Gray
Write-Host ""
Write-Host "2. 配置 Telegram Bot:" -ForegroundColor Cyan
Write-Host "   - 打开 @BotFather" -ForegroundColor Gray
Write-Host "   - 发送 /mybots" -ForegroundColor Gray
Write-Host "   - 选择你的 Bot → Bot Settings → Menu Button" -ForegroundColor Gray
Write-Host "   - 输入 WebApp 链接" -ForegroundColor Gray
Write-Host ""
Write-Host "3. 测试游戏:" -ForegroundColor Cyan
Write-Host "   - 在 Telegram 中点击菜单按钮" -ForegroundColor Gray
Write-Host ""

# 可选：检查 Godot 是否可用
Write-Host "[可选] 重新导出:" -ForegroundColor Yellow
$godotPath = Get-Command godot -ErrorAction SilentlyContinue
if ($godotPath) {
    Write-Host "   Godot 路径: $($godotPath.Source)" -ForegroundColor Gray
    Write-Host "   运行: godot --path '$ProjectPath' --export-release 'Web' 'export/web/index.html'" -ForegroundColor Gray
} else {
    Write-Warning "未找到 Godot CLI，请手动导出 Web 版本"
}

Write-Host ""

exit ($allPassed ? 0 : 1)
