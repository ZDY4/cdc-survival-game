<#
.SYNOPSIS
Runs deterministic Godot game smoke scenarios.

.DESCRIPTION
This script is the repo-local agent entrypoint for Godot runtime smoke checks.
It runs Godot 4.6.3 headless scripts from `godot/scripts/tools/`, captures console
output, and writes a JSON result under `.local/agent-smoke/godot_game`.

.PARAMETER Scenario
Smoke scenario to run. Use `All` to run every migrated Godot smoke scenario.

.PARAMETER OutputRoot
Directory for console logs and JSON result output. Defaults to `.local/agent-smoke/godot_game`.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-game.ps1

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All
#>
[CmdletBinding()]
param(
    [ValidateSet(
        "All",
        "Runtime",
        "ContentCLI",
        "ContentEdit",
        "MapEdit",
        "EditorHandoff",
        "EditorBrowser",
        "MapPreview",
        "World",
        "Scene",
        "Overworld",
        "Movement",
        "Vision",
        "AI",
        "Interaction",
        "PlayerInteraction",
        "UI",
        "DialogueUI",
        "DialogueAction",
        "InventoryUI",
        "ContainerUI",
        "JournalUI",
        "TradeUI",
        "Quest",
        "Combat",
        "Progression",
        "Equipment",
        "Crafting",
        "Save"
    )]
    [string]$Scenario = "All",

    [string]$OutputRoot,

    [string]$Godot = "D:\godot\godot.cmd"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\agent-smoke\godot_game"
}
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot command not found: $Godot"
}

$scenarioScripts = [ordered]@{
    Runtime           = "res://scripts/tools/runtime_smoke.gd"
    ContentCLI        = "res://scripts/tools/content_cli_smoke.gd"
    ContentEdit       = "res://scripts/tools/content_edit_service_smoke.gd"
    MapEdit           = "res://scripts/tools/map_edit_service_smoke.gd"
    EditorHandoff     = "res://scripts/tools/editor_handoff_smoke.gd"
    EditorBrowser     = "res://scripts/tools/editor_content_browser_smoke.gd"
    MapPreview        = "res://scripts/tools/map_preview_smoke.gd"
    World             = "res://scripts/tools/world_smoke.gd"
    Scene             = "res://scripts/tools/scene_smoke.gd"
    Overworld         = "res://scripts/tools/overworld_smoke.gd"
    Movement          = "res://scripts/tools/movement_smoke.gd"
    Vision            = "res://scripts/tools/vision_smoke.gd"
    AI                = "res://scripts/tools/ai_smoke.gd"
    Interaction       = "res://scripts/tools/interaction_smoke.gd"
    PlayerInteraction = "res://scripts/tools/player_interaction_smoke.gd"
    UI                = "res://scripts/tools/ui_smoke.gd"
    DialogueUI        = "res://scripts/tools/dialogue_ui_smoke.gd"
    DialogueAction    = "res://scripts/tools/dialogue_action_smoke.gd"
    InventoryUI       = "res://scripts/tools/inventory_ui_smoke.gd"
    ContainerUI       = "res://scripts/tools/container_ui_smoke.gd"
    JournalUI         = "res://scripts/tools/journal_ui_smoke.gd"
    TradeUI           = "res://scripts/tools/trade_ui_smoke.gd"
    Quest             = "res://scripts/tools/quest_smoke.gd"
    Combat            = "res://scripts/tools/combat_smoke.gd"
    Progression       = "res://scripts/tools/progression_smoke.gd"
    Equipment         = "res://scripts/tools/equipment_smoke.gd"
    Crafting          = "res://scripts/tools/crafting_smoke.gd"
    Save              = "res://scripts/tools/save_smoke.gd"
}

$selected = @()
if ($Scenario -eq "All") {
    $selected = @($scenarioScripts.Keys)
} else {
    $selected = @($Scenario)
}

$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$startedAt = Get-Date
$status = "passed"
$results = @()

Push-Location $repoRoot
try {
    foreach ($name in $selected) {
        $scriptPath = $scenarioScripts[$name]
        $consoleLog = Join-Path $runRoot ("{0}.log" -f $name)
        Write-Host "Running Godot smoke scenario '$name' with script '$scriptPath'"
        & $Godot --headless --path godot --script $scriptPath 2>&1 |
            Tee-Object -FilePath $consoleLog
        $exitCode = $LASTEXITCODE
        $scenarioStatus = if ($exitCode -eq 0) { "passed" } else { "failed" }
        if ($exitCode -ne 0) {
            $status = "failed"
        }
        $results += [PSCustomObject]@{
            scenario = $name
            script = $scriptPath
            status = $scenarioStatus
            exitCode = $exitCode
            consoleLog = $consoleLog
        }
        if ($exitCode -ne 0) {
            break
        }
    }
}
finally {
    Pop-Location
}

$resultPath = Join-Path $runRoot "result.json"
$result = [PSCustomObject]@{
    scenario = $Scenario
    status = $status
    startedAt = $startedAt.ToString("o")
    finishedAt = (Get-Date).ToString("o")
    results = $results
}
$result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath

if ($status -ne "passed") {
    Write-Error "Godot game smoke failed; see $resultPath"
}

Write-Host "Godot game smoke result written to $resultPath"
