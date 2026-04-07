@echo off
setlocal

set SURFACE=%~1
if "%SURFACE%"=="" set SURFACE=items

pushd "%~dp0tools\tauri_editor" || exit /b 1
call npm run tauri:dev:%SURFACE%
set EXIT_CODE=%ERRORLEVEL%
popd

exit /b %EXIT_CODE%
