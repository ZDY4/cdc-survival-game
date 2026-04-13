@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "PWSH_EXE=pwsh"
set "MODE=%~1"

if "%MODE%"=="" set "MODE=offline"

%PWSH_EXE% -NoLogo -NoProfile -File "%ROOT_DIR%tools\narrative_lab\scripts\run_narrative_chat_regression.ps1" -Mode %MODE%
exit /b %ERRORLEVEL%
