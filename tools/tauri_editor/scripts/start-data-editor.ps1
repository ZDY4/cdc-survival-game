$ErrorActionPreference = "Stop"

param(
    [ValidateSet("items", "dialogues", "quests")]
    [string]$Surface = "items"
)

$editorRoot = Join-Path $PSScriptRoot ".."
Set-Location $editorRoot

npm run "tauri:dev:$Surface"
