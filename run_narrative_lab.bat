@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "EDITOR_DIR=%ROOT_DIR%tools\narrative_lab"
set "CARGO_EXE=%USERPROFILE%\.cargo\bin\cargo.exe"
set "NPM_EXE=npm.cmd"
set "VSDEVCMD="
set "VSWHERE="
set "SELF_TEST_SCENARIO="
set "PORT_1421_PID="

if /I "%~1"=="--self-test" (
    set "SELF_TEST_SCENARIO=narrative-menu"
)

if not exist "%EDITOR_DIR%\package.json" (
    echo [ERROR] Narrative Lab project not found: "%EDITOR_DIR%"
    exit /b 1
)

if exist "%CARGO_EXE%" (
    for %%F in ("%CARGO_EXE%") do set "PATH=%%~dpF;%PATH%"
) else (
    where cargo >nul 2>nul
    if errorlevel 1 (
        echo [ERROR] cargo executable not found.
        echo [ERROR] Install Rust or add Cargo to PATH.
        exit /b 1
    )
    set "CARGO_EXE=cargo"
)

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

for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:"127\.0\.0\.1:1421 .*LISTENING" /C:"0\.0\.0\.0:1421 .*LISTENING" /C:"\[::1\]:1421 .*LISTENING" /C:"\[::\]:1421 .*LISTENING"') do (
    set "PORT_1421_PID=%%P"
    goto :port_1421_in_use
)

pushd "%EDITOR_DIR%"
call "%VSDEVCMD%" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 (
    popd
    echo [ERROR] Failed to initialize Visual Studio build environment.
    exit /b 1
)

if not exist "node_modules" goto :install_npm_deps
if not exist "node_modules\react-markdown" goto :install_npm_deps
if not exist "node_modules\remark-gfm" goto :install_npm_deps
goto :start_narrative_lab

:install_npm_deps
if not exist "node_modules" (
    echo Installing Narrative Lab npm dependencies...
) else (
    echo Narrative Lab npm dependencies are missing or incomplete. Reinstalling...
)
call %NPM_EXE% install
if errorlevel 1 (
    set "EXIT_CODE=%ERRORLEVEL%"
    popd
    echo [ERROR] npm install failed.
    exit /b %EXIT_CODE%
)

:start_narrative_lab
if defined SELF_TEST_SCENARIO (
    echo Starting Narrative Lab in self-test mode: %SELF_TEST_SCENARIO%
    set "CDC_EDITOR_SELF_TEST=%SELF_TEST_SCENARIO%"
) else (
    echo Starting Narrative Lab...
)
call %NPM_EXE% run tauri:dev
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%

:port_1421_in_use
echo [ERROR] Port 1421 is already in use, so Narrative Lab cannot start its Vite dev server.
if defined PORT_1421_PID (
    echo [ERROR] Listening PID: %PORT_1421_PID%
    tasklist /FI "PID eq %PORT_1421_PID%" | findstr /V /C:"INFO:" 
)
echo [ERROR] Close the process above, or stop the existing dev server on http://localhost:1421 and try again.
exit /b 1
