@echo off
chcp 65001 > nul
echo ==========================================
echo CDC末日生存游戏 - H5版本自动导出
echo ==========================================
echo.

REM 设置路径
set PROJECT_PATH=G:\project\cdc_survival_game
set GODOT_EXE=godot

cd /d %PROJECT_PATH%

echo [1/3] 检查Godot安装...
%GODOT_EXE% --version
if errorlevel 1 (
    echo ❌ 错误：找不到Godot。请确保Godot 4.6已安装并在PATH中。
    pause
    exit /b 1
)
echo ✅ Godot检查通过
echo.

echo [2/3] 清理并准备导出目录...
if exist "export\web" rmdir /s /q "export\web"
mkdir "export\web"
echo ✅ 导出目录准备完成
echo.

echo [3/3] 导出Web版本...
echo 这可能需要几分钟时间，请耐心等待...
echo.

%GODOT_EXE% --path %PROJECT_PATH% --export-release "Web" "export/web/index.html"

if errorlevel 1 (
    echo.
    echo ❌ 导出失败！
    echo 请检查：
    echo   1. Godot 4.6 Web导出模板是否已安装
    echo   2. export_presets.cfg 是否正确配置
    pause
    exit /b 1
)

echo.
echo ==========================================
echo ✅ Web版本导出成功！
echo ==========================================
echo.
echo 导出文件列表：
dir /b export\web
echo.
echo 文件大小：
for %%f in (export\web\*) do (
    echo   %%~nxf: %%~zf bytes
)
echo.
echo 如需上传到腾讯COS，请运行：
echo   python tools\cos_helper.py
echo.
pause
