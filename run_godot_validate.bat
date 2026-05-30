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

echo Running Godot content validation...
call "%GODOT_EXE%" --headless --path "%ROOT_DIR%godot" --script res://scripts/tools/validate_all.gd %*
if errorlevel 1 exit /b %ERRORLEVEL%

echo Running Godot migration guard...
call "%GODOT_EXE%" --headless --path "%ROOT_DIR%godot" --script res://scripts/tools/mainline_migration_guard.gd
exit /b %ERRORLEVEL%
