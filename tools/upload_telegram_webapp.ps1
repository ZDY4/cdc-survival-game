# CDC Survival Game - Telegram WebApp Upload Script
# 上传到腾讯云 COS

param(
    [string]$Bucket = "cdc-survival-game-xxxxxxxx",
    [string]$Region = "ap-guangzhou",
    [string]$LocalPath = "G:\project\cdc_survival_game\export\web",
    [string]$CosPath = "/telegram-webapp",
    [switch]$Force
)

# 颜色输出
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput Cyan "========================================"
Write-ColorOutput Cyan "CDC 末日生存 - Telegram WebApp 上传脚本"
Write-ColorOutput Cyan "========================================"
Write-Output ""

# 检查本地目录
if (-not (Test-Path $LocalPath)) {
    Write-ColorOutput Red "错误: 本地目录不存在: $LocalPath"
    exit 1
}

# 检查 coscmd 是否安装
try {
    $coscmdVersion = coscmd --version 2>$null
    if (-not $coscmdVersion) {
        throw "coscmd not found"
    }
    Write-ColorOutput Green "✓ COSCMD 已安装"
} catch {
    Write-ColorOutput Yellow "警告: COSCMD 未安装，尝试使用 Python 版本..."
    try {
        $pipVersion = pip --version 2>$null
        if ($pipVersion) {
            Write-Output "正在安装 coscmd..."
            pip install coscmd
        } else {
            throw "pip not found"
        }
    } catch {
        Write-ColorOutput Red "错误: 无法安装 COSCMD，请手动安装:"
        Write-Output "pip install coscmd"
        exit 1
    }
}

# 文件列表
$files = @(
    "index.html",
    "index.js",
    "index.wasm",
    "index.pck",
    "index.png",
    "index.icon.png",
    "index.apple-touch-icon.png",
    "index.audio.worklet.js",
    "index.audio.position.worklet.js",
    "telegram_webapp_bridge.js"
)

Write-Output ""
Write-ColorOutput Yellow "准备上传以下文件:"
Write-Output "----------------------------------------"

$totalSize = 0
foreach ($file in $files) {
    $filePath = Join-Path $LocalPath $file
    if (Test-Path $filePath) {
        $size = (Get-Item $filePath).Length
        $totalSize += $size
        $sizeStr = if ($size -gt 1MB) {
            "{0:N2} MB" -f ($size / 1MB)
        } elseif ($size -gt 1KB) {
            "{0:N2} KB" -f ($size / 1KB)
        } else {
            "$size B"
        }
        Write-Output "  ✓ $file ($sizeStr)"
    } else {
        Write-ColorOutput Red "  ✗ $file (缺失)"
    }
}

$totalSizeStr = if ($totalSize -gt 1MB) {
    "{0:N2} MB" -f ($totalSize / 1MB)
} else {
    "{0:N2} KB" -f ($totalSize / 1KB)
}

Write-Output "----------------------------------------"
Write-Output "总大小: $totalSizeStr"
Write-Output ""

# 确认上传
if (-not $Force) {
    $confirm = Read-Host "确认上传? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-ColorOutput Yellow "上传已取消"
        exit 0
    }
}

# 执行上传
Write-ColorOutput Cyan "开始上传..."
Write-Output ""

$successCount = 0
$failCount = 0

foreach ($file in $files) {
    $localFile = Join-Path $LocalPath $file
    $remoteFile = "$CosPath/$file"
    
    if (-not (Test-Path $localFile)) {
        Write-ColorOutput Yellow "跳过缺失文件: $file"
        continue
    }
    
    Write-Output "上传: $file ..." -NoNewline
    
    try {
        $result = coscmd upload "$localFile" "$remoteFile" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput Green " 成功"
            $successCount++
        } else {
            throw "Upload failed"
        }
    } catch {
        Write-ColorOutput Red " 失败"
        Write-ColorOutput Red "  错误: $_"
        $failCount++
    }
}

Write-Output ""
Write-Output "----------------------------------------"
Write-ColorOutput Green "上传完成: $successCount 成功, $failCount 失败"
Write-Output ""

# 设置文件权限 (公共读)
Write-ColorOutput Cyan "设置文件权限..."
foreach ($file in $files) {
    $remoteFile = "$CosPath/$file"
    try {
        coscmd putobjectacl --grant-read anyuser "$remoteFile" 2>$null
    } catch {
        # 忽略权限设置错误
    }
}

# 输出访问链接
Write-Output ""
Write-ColorOutput Cyan "========================================"
Write-ColorOutput Cyan "访问链接"
Write-ColorOutput Cyan "========================================"
Write-Output ""
Write-Output "Web 版本:"
Write-ColorOutput Green "  https://$Bucket.cos.$Region.myqcloud.com$CosPath/index.html"
Write-Output ""
Write-Output "Telegram WebApp (配置到 Bot):"
Write-ColorOutput Green "  https://$Bucket.cos.$Region.myqcloud.com$CosPath/index.html"
Write-Output ""
Write-Output "BotFather 设置命令:"
Write-Output "  /setmenubutton"
Write-Output "  然后输入上述链接"
Write-Output ""

# 生成 Telegram Bot 配置提示
Write-ColorOutput Cyan "========================================"
Write-ColorOutput Cyan "Telegram Bot 配置"
Write-ColorOutput Cyan "========================================"
Write-Output ""
Write-Output "1. 打开 @BotFather"
Write-Output "2. 发送 /mybots"
Write-Output "3. 选择你的 Bot"
Write-Output "4. 选择 'Bot Settings'"
Write-Output "5. 选择 'Menu Button'"
Write-Output "6. 选择 'Configure menu button'"
Write-Output "7. 输入: https://$Bucket.cos.$Region.myqcloud.com$CosPath/index.html"
Write-Output ""
Write-ColorOutput Green "完成！用户点击菜单按钮即可启动游戏。"
Write-Output ""
