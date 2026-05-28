@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "GODOT_EXE=D:\godot\godot.cmd"

if not exist "%GODOT_EXE%" (
    echo [ERROR] Godot command not found: "%GODOT_EXE%"
    exit /b 1
)

if not exist "%ROOT_DIR%godot\project.godot" (
    echo [ERROR] Godot project not found: "%ROOT_DIR%godot\project.godot"
    exit /b 1
)

echo Starting Godot Editor...
"%GODOT_EXE%" --editor --path "%ROOT_DIR%godot" %*
exit /b %ERRORLEVEL%
