@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "RUST_DIR=%ROOT_DIR%rust"
set "TARGET_DIR=%RUST_DIR%\target"
set "DEBUG_DIR=%TARGET_DIR%\debug"
set "RELEASE_DIR=%TARGET_DIR%\release"
set "LOG_DIR=%ROOT_DIR%logs"
set "ROOT_TARGET_DIR=%ROOT_DIR%target"
set "TMP_DIR=%ROOT_DIR%tmp"
set "NPM_CACHE_DIR=%ROOT_DIR%tools\npm-cache"
set "NPM_CACHE_LOG_DIR=%NPM_CACHE_DIR%\_logs"
set "NPM_CACHE_NOTIFIER_FILE=%NPM_CACHE_DIR%\_update-notifier-last-checked"
set "LOG_RETENTION_DAYS=3"
set "AUTO_YES=0"

if /I "%~1"=="--yes" set "AUTO_YES=1"
if /I "%~1"=="-y" set "AUTO_YES=1"

if not exist "%RUST_DIR%\Cargo.toml" (
    echo [ERROR] Rust workspace not found: "%RUST_DIR%"
    exit /b 1
)

echo This script will clean project-generated files under:
echo   "%TARGET_DIR%"
echo   "%LOG_DIR%"
echo   "%ROOT_TARGET_DIR%"
echo   "%TMP_DIR%"
echo   "%NPM_CACHE_LOG_DIR%"
echo.
echo It will clean:
echo   - debug\incremental
echo   - debug\*.pdb
echo   - debug\deps\*.pdb
echo   - release\*.pdb
echo   - release\deps\*.pdb
echo   - log files older than %LOG_RETENTION_DAYS% days under logs\
echo   - *.log files older than %LOG_RETENTION_DAYS% days under target\
echo   - tmp\narrative_lab_regression_* directories older than %LOG_RETENTION_DAYS% days
echo   - npm cache log files older than %LOG_RETENTION_DAYS% days
echo   - tools\npm-cache\_update-notifier-last-checked
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

call :clean_target_cache
if errorlevel 1 exit /b 1

call :clean_expired_logs
if errorlevel 1 exit /b 1

call :clean_root_target_logs
if errorlevel 1 exit /b 1

call :clean_expired_tmp_outputs
if errorlevel 1 exit /b 1

call :clean_npm_cache_logs
if errorlevel 1 exit /b 1

echo.
echo [DONE] Project cleanup finished.
echo [TIP] If you ever want a full Rust cleanup, run:
echo   cd /d "%RUST_DIR%"
echo   cargo clean

exit /b 0

:clean_target_cache
if not exist "%TARGET_DIR%" (
    echo [INFO] Skipping Rust target cleanup. Directory not found: "%TARGET_DIR%"
    exit /b 0
)

call :remove_dir_if_exists "%DEBUG_DIR%\incremental"
call :remove_files_if_exist "%DEBUG_DIR%\*.pdb"
call :remove_files_if_exist "%DEBUG_DIR%\deps\*.pdb"
call :remove_files_if_exist "%RELEASE_DIR%\*.pdb"
call :remove_files_if_exist "%RELEASE_DIR%\deps\*.pdb"
exit /b 0

:clean_expired_logs
if not exist "%LOG_DIR%" (
    echo [INFO] Skipping log cleanup. Directory not found: "%LOG_DIR%"
    exit /b 0
)

echo [CLEAN] Removing log files older than %LOG_RETENTION_DAYS% days under "%LOG_DIR%"
pwsh -NoLogo -NoProfile -Command ^
  "$cutoff = (Get-Date).AddDays(-[int]$env:LOG_RETENTION_DAYS);" ^
  "$logRoot = $env:LOG_DIR;" ^
  "$expiredFiles = Get-ChildItem -LiteralPath $logRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff };" ^
  "foreach ($file in $expiredFiles) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop };" ^
  "$emptyDirectories = Get-ChildItem -LiteralPath $logRoot -Recurse -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) };" ^
  "foreach ($directory in $emptyDirectories) { Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue };" ^
  "Write-Host ('[DONE] Removed ' + $expiredFiles.Count + ' expired log file(s).')"
if errorlevel 1 (
    echo [ERROR] Failed to clean expired logs under "%LOG_DIR%"
    exit /b 1
)
exit /b 0

:clean_root_target_logs
if not exist "%ROOT_TARGET_DIR%" (
    echo [INFO] Skipping root target log cleanup. Directory not found: "%ROOT_TARGET_DIR%"
    exit /b 0
)

echo [CLEAN] Removing *.log files older than %LOG_RETENTION_DAYS% days under "%ROOT_TARGET_DIR%"
pwsh -NoLogo -NoProfile -Command ^
  "$cutoff = (Get-Date).AddDays(-[int]$env:LOG_RETENTION_DAYS);" ^
  "$targetRoot = $env:ROOT_TARGET_DIR;" ^
  "$expiredFiles = Get-ChildItem -LiteralPath $targetRoot -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff };" ^
  "foreach ($file in $expiredFiles) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop };" ^
  "Write-Host ('[DONE] Removed ' + $expiredFiles.Count + ' expired target log file(s).')"
if errorlevel 1 (
    echo [ERROR] Failed to clean expired target logs under "%ROOT_TARGET_DIR%"
    exit /b 1
)
exit /b 0

:clean_expired_tmp_outputs
if not exist "%TMP_DIR%" (
    echo [INFO] Skipping tmp cleanup. Directory not found: "%TMP_DIR%"
    exit /b 0
)

echo [CLEAN] Removing narrative_lab_regression_* directories older than %LOG_RETENTION_DAYS% days under "%TMP_DIR%"
pwsh -NoLogo -NoProfile -Command ^
  "$cutoff = (Get-Date).AddDays(-[int]$env:LOG_RETENTION_DAYS);" ^
  "$tmpRoot = $env:TMP_DIR;" ^
  "$expiredDirs = Get-ChildItem -LiteralPath $tmpRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'narrative_lab_regression_*' -and $_.LastWriteTime -lt $cutoff };" ^
  "foreach ($directory in $expiredDirs) { Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction Stop };" ^
  "Write-Host ('[DONE] Removed ' + $expiredDirs.Count + ' expired tmp regression directorie(s).')"
if errorlevel 1 (
    echo [ERROR] Failed to clean expired tmp outputs under "%TMP_DIR%"
    exit /b 1
)
exit /b 0

:clean_npm_cache_logs
if not exist "%NPM_CACHE_DIR%" (
    echo [INFO] Skipping npm cache cleanup. Directory not found: "%NPM_CACHE_DIR%"
    exit /b 0
)

if exist "%NPM_CACHE_NOTIFIER_FILE%" (
    echo [CLEAN] Removing "%NPM_CACHE_NOTIFIER_FILE%"
    del /Q "%NPM_CACHE_NOTIFIER_FILE%"
)

if not exist "%NPM_CACHE_LOG_DIR%" (
    echo [INFO] Skipping npm cache log cleanup. Directory not found: "%NPM_CACHE_LOG_DIR%"
    exit /b 0
)

echo [CLEAN] Removing npm cache log files older than %LOG_RETENTION_DAYS% days under "%NPM_CACHE_LOG_DIR%"
pwsh -NoLogo -NoProfile -Command ^
  "$cutoff = (Get-Date).AddDays(-[int]$env:LOG_RETENTION_DAYS);" ^
  "$logRoot = $env:NPM_CACHE_LOG_DIR;" ^
  "$expiredFiles = Get-ChildItem -LiteralPath $logRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff };" ^
  "foreach ($file in $expiredFiles) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop };" ^
  "$emptyDirectories = Get-ChildItem -LiteralPath $logRoot -Recurse -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) };" ^
  "foreach ($directory in $emptyDirectories) { Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue };" ^
  "Write-Host ('[DONE] Removed ' + $expiredFiles.Count + ' expired npm cache log file(s).')"
if errorlevel 1 (
    echo [ERROR] Failed to clean npm cache logs under "%NPM_CACHE_LOG_DIR%"
    exit /b 1
)
exit /b 0

:remove_dir_if_exists
if exist "%~1" (
    echo [CLEAN] Removing "%~1"
    rmdir /S /Q "%~1" 2>nul
    if exist "%~1" (
        echo [WARN] Could not fully remove "%~1". Some files may still be in use.
    )
)
exit /b 0

:remove_files_if_exist
if exist "%~1" (
    echo [CLEAN] Removing "%~1"
    del /Q "%~1" 2>nul
    if exist "%~1" (
        echo [WARN] Could not fully remove "%~1". Some files may still be in use.
    )
)
exit /b 0
