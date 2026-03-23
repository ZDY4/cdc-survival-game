@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "EDITOR_DIR=%ROOT_DIR%tools\tauri_editor"
set "CARGO_DIR=%USERPROFILE%\.cargo\bin"
set "NPM_EXE=npm.cmd"
set "VSDEVCMD="
set "VSWHERE="

if not exist "%EDITOR_DIR%\package.json" (
    echo [ERROR] Tauri editor project not found: "%EDITOR_DIR%"
    exit /b 1
)

if not exist "%CARGO_DIR%\cargo.exe" (
    echo [ERROR] cargo.exe not found in "%CARGO_DIR%"
    echo [ERROR] Please install Rust with rustup first.
    exit /b 1
)

set "PATH=%CARGO_DIR%;%PATH%"

for %%F in (
    "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    "%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
) do (
    if exist %%~F (
        set "VSWHERE=%%~F"
        goto :vswhere_found
    )
)

:vswhere_found
if defined VSWHERE (
    for /f "usebackq delims=" %%F in (`"%VSWHERE%" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find Common7\Tools\VsDevCmd.bat`) do (
        set "VSDEVCMD=%%F"
        goto :vsdev_found
    )
)

for %%F in (
    "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files\Microsoft Visual Studio\17\Community\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files\Microsoft Visual Studio\17\BuildTools\Common7\Tools\VsDevCmd.bat"
) do (
    if exist %%~F (
        set "VSDEVCMD=%%~F"
        goto :vsdev_found
    )
)

echo [ERROR] VsDevCmd.bat not found. Please install Visual Studio Build Tools with Desktop development with C++.
exit /b 1

:vsdev_found
where %NPM_EXE% >nul 2>nul
if errorlevel 1 (
    echo [ERROR] npm.cmd not found in PATH.
    echo [ERROR] Please install Node.js first.
    exit /b 1
)

pushd "%EDITOR_DIR%"
call "%VSDEVCMD%" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 (
    popd
    echo [ERROR] Failed to initialize Visual Studio build environment.
    exit /b 1
)

if not exist "node_modules" (
    echo Installing tauri_editor npm dependencies...
    call %NPM_EXE% install
    if errorlevel 1 (
        set "EXIT_CODE=%ERRORLEVEL%"
        popd
        echo [ERROR] npm install failed.
        exit /b %EXIT_CODE%
    )
)

echo Starting tauri_editor...
call %NPM_EXE% run tauri -- dev
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%
