@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "RUST_DIR=%ROOT_DIR%rust"
set "CARGO_EXE=%USERPROFILE%\.cargo\bin\cargo.exe"

if not exist "%RUST_DIR%\Cargo.toml" (
    echo [ERROR] Rust workspace not found: "%RUST_DIR%"
    exit /b 1
)

if not exist "%CARGO_EXE%" (
    where cargo >nul 2>nul
    if errorlevel 1 (
        echo [ERROR] cargo executable not found. Install Rust or add Cargo to PATH.
        exit /b 1
    )
    set "CARGO_EXE=cargo"
)

pushd "%RUST_DIR%"

echo Starting bevy_debug_viewer...
"%CARGO_EXE%" run -p bevy_debug_viewer
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%
