$ErrorActionPreference = "Stop"

$editorRoot = Join-Path $PSScriptRoot ".."
Set-Location $editorRoot

npm run tauri:data
