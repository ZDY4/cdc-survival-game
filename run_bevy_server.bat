@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "RUST_DIR=%ROOT_DIR%rust"
set "VSDEVCMD=C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat"
set "CARGO_EXE=%USERPROFILE%\.cargo\bin\cargo.exe"

if not exist "%RUST_DIR%\Cargo.toml" (
    echo [ERROR] Rust workspace not found: "%RUST_DIR%"
    exit /b 1
)

if not exist "%VSDEVCMD%" (
    echo [ERROR] VsDevCmd.bat not found: "%VSDEVCMD%"
    exit /b 1
)

if not exist "%CARGO_EXE%" (
    set "CARGO_EXE=cargo"
)

pushd "%RUST_DIR%"
call "%VSDEVCMD%" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 (
    popd
    echo [ERROR] Failed to initialize Visual Studio build environment.
    exit /b 1
)

echo Starting bevy_server...
"%CARGO_EXE%" run -p bevy_server
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%
