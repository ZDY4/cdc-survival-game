@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "RUST_DIR=%ROOT_DIR%rust"
set "TARGET_DIR=%RUST_DIR%\target"
set "DEBUG_DIR=%TARGET_DIR%\debug"
set "RELEASE_DIR=%TARGET_DIR%\release"

if not exist "%RUST_DIR%\Cargo.toml" (
    echo [ERROR] Rust workspace not found: "%RUST_DIR%"
    exit /b 1
)

if not exist "%TARGET_DIR%" (
    echo [INFO] Nothing to clean. Target directory not found: "%TARGET_DIR%"
    exit /b 0
)

set "AUTO_YES=0"
if /I "%~1"=="--yes" set "AUTO_YES=1"
if /I "%~1"=="-y" set "AUTO_YES=1"

echo This script will remove Rust build cache files under:
echo   "%TARGET_DIR%"
echo.
echo It will clean:
echo   - debug\incremental
echo   - debug\*.pdb
echo   - debug\deps\*.pdb
echo   - release\*.pdb
echo   - release\deps\*.pdb
echo.
echo It will NOT run "cargo clean".
echo.

if "%AUTO_YES%"=="0" (
    choice /C YN /N /M "Continue? [Y/N]: "
    if errorlevel 2 (
        echo [INFO] Cancelled.
        exit /b 0
    )
)

if exist "%DEBUG_DIR%\incremental" (
    echo [CLEAN] Removing "%DEBUG_DIR%\incremental"
    rmdir /S /Q "%DEBUG_DIR%\incremental"
)

if exist "%DEBUG_DIR%\*.pdb" (
    echo [CLEAN] Removing "%DEBUG_DIR%\*.pdb"
    del /Q "%DEBUG_DIR%\*.pdb"
)

if exist "%DEBUG_DIR%\deps\*.pdb" (
    echo [CLEAN] Removing "%DEBUG_DIR%\deps\*.pdb"
    del /Q "%DEBUG_DIR%\deps\*.pdb"
)

if exist "%RELEASE_DIR%\*.pdb" (
    echo [CLEAN] Removing "%RELEASE_DIR%\*.pdb"
    del /Q "%RELEASE_DIR%\*.pdb"
)

if exist "%RELEASE_DIR%\deps\*.pdb" (
    echo [CLEAN] Removing "%RELEASE_DIR%\deps\*.pdb"
    del /Q "%RELEASE_DIR%\deps\*.pdb"
)

echo.
echo [DONE] Rust target cleanup finished.
echo [TIP] If you ever want a full cleanup, run:
echo   cd /d "%RUST_DIR%"
echo   cargo clean

exit /b 0
